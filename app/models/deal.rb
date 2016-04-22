class Deal < ActiveRecord::Base
  unloadable

  BASE_TYPES = %w(user contact).freeze

  def self.connect_to_base
    begin
      client = BaseCRM::Client.new(
        access_token: Setting.plugin_basecrm[:base_token]
      )
    rescue
      return { error: l(:client_error) }
    end
    # '5dd38d5b675c56f9651b42ff66dde2d74971d0490c6af94aa66cf3e87b47b801')
    begin
      sync = BaseCRM::Sync.new(
        client: client,
        device_uuid: Setting.plugin_basecrm[:device_uuid]
      )
    rescue
      return { error: l(:sync_error) }
    end

    Deal.sync_data(sync)
  end

  def self.sync_data(sync)
    resources = []
    deals = []
    notes = []
    sources = {}
    stages = {}

    sync.fetch do |meta, resource|
      case meta.type.to_s
      when 'deal'
        deals.push(resource)
        meta.sync.ack
      when 'user', 'contact'
        resources.push(resource)
      when 'pipeline'
        stages = Deal.pipeline_stages(resource)
      when 'source'
        sources[resource.id] = resource.name
      when 'note'
        notes.push(resource)
        meta.sync.ack
      else
        meta.sync.ack
      end
    end

    {
      deals: deals,
      resources: resources,
      notes: notes,
      sources: sources,
      stages: stages
    }
  end

  def self.pipeline_stages(resource)
    stages = {}
    resource.stages[:items].each do |item|
      stages[item[:data][:id]] = item[:data][:name]
    end
    stages
  end

  def self.create_or_update_issue(deal, options)
    issue_id = Deal.find_issue_id(deal)

    if issue_id.present?
      Deal.update_issue(deal, issue_id, options)
    else
      issue_id = Deal.create_issue(deal, options[:resources])
    end


    if options[:stages][deal.stage_id] == 'Won'
      Issue.find(issue_id)
           .update_attribute(:category_id, Setting.plugin_basecrm[:category_id])
    end
  end

  def self.create_issue(deal, resources)
    author_id = Deal.assign_to(Deal.user_name(deal.owner_id, resources))
    issue = Issue.new(
      tracker_id: Setting.plugin_basecrm[:tracker_id],
      project_id: Setting.plugin_basecrm[:project_id],
      priority: IssuePriority.find_by_position_name('default'),
      subject: "DID: #{deal.id} - #{deal.name}",
      description: Deal.description(deal, resources),
      author_id: author_id || User.current.id,
      assigned_to_id: author_id
    )

    IssueRevision.create_revision(issue.id, deal) if issue.save

    issue.id
  end

  def self.update_issue(deal, issue_id, options)
    deal_notes = Deal.find_notes(deal.id, options[:notes])
    deal_notes.each do |note|
      if Deal.create_note(issue_id, note, options[:resources])
        Issue.find(issue_id).touch
      end
    end

    diff = IssueRevision.differences(deal, issue_id)
    if diff.present?
      note = IssueRevision.note(deal.creator_id, diff, options)
      IssueRevision.create_note(issue_id, note)
    end

    IssueRevision.create_revision(issue_id, deal)
  end

  def self.create_note(issue_id, note, resources)
    author_id = Deal.assign_to(Deal.user_name(note.creator_id, resources))
    j = Journal.new(
      journalized_id: issue_id,
      journalized_type: 'Issue',
      user_id: author_id || User.current.id,
      notes: Deal.note(note, resources),
    )

    j.save
  end

  def self.description(deal, resources)
    items = []

    link = "https://app.futuresimple.com/sales/deals/#{deal.id}"

    items << "Contact Name: #{Deal.contact_name(deal.contact_id, resources)}" unless deal.contact_id.nil?
    items << "Company Name: #{Deal.contact_name(deal.organization_id, resources)}" unless deal.organization_id.nil?
    items << "User name: #{Deal.user_name(deal.owner_id, resources)}"
    items << "Scope: #{deal.value} #{deal.currency}"
    items << "Link: #{link}"

    Setting.plugin_basecrm[:html_tags] ? items.join('<br />') : items.join("\r\n")
  end

  def self.note(note, resources)
    items = []

    items << "Deal edited by: #{Deal.user_name(note.creator_id, resources)}"
    items << "Deal edited at: #{note.created_at.gsub(/[a-zA-Z]/, ' ')}"
    items << 'Content:'
    items << note.content

    Setting.plugin_basecrm[:html_tags] ? items.join('<br />') : items.join("\r\n")
  end

  def self.contact_name(id, resources)
    resources.each do |resource|
      return resource.name if resource.id == id && resource.is_organization
      return "#{resource.first_name} #{resource.last_name}" if resource.id == id
    end
    nil
  end

  def self.user_name(id, resources)
    resources.each do |resource|
      return resource.name if resource.id == id
    end
    nil
  end

  def self.assign_to(full_name)
    names = full_name.split(' ')
    assignee = User.where(firstname: names[0], lastname: names[1]).first
    return assignee.id unless assignee.nil?
  end

  def self.find_issue_id(deal)
    issue_id = nil
    IssueRevision.all.each do |rev|
      issue_id = rev.issue_id if JSON.parse(rev.deal_info)['id'] == deal.id
    end
    issue_id
  end

  # def self.id_from_issue(subject)
  #   arr = subject.split(' ')
  #   arr[0] == 'DID:' ? arr[1] : nil
  # end

  # def self.already_exists?(issues, deal_id)
  #   issues.each do |issue|
  #     return true if issue['subject'] == deal_id
  #   end
  #   false
  # end

  # def self.issue_from_base(deal_id)
  #   Issue.connection.select_all(Issue.select('id, subject')).each do |issue|
  #     t = Deal.id_from_issue(issue['subject'])
  #     return issue if t.present? && t == deal_id
  #   end
  #   nil
  # end

  def self.find_notes(deal_id, notes)
    deal_notes = []
    notes.each do |note|
      deal_notes.push(note) if note.resource_id == deal_id
    end
    deal_notes
  end
end
