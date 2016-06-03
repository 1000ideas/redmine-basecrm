class Deal < ActiveRecord::Base
  unloadable

  REDUNDANT_KEYS = [:last_activity_at,
                    :updated_at,
                    :associated_contacts,
                    :contact_id,
                    :dropbox_email
                   ].freeze

  def self.basecrm_logger
    @@basecrm_logger ||= Logger.new("#{Rails.root}/log/basecrm.log")
  end

  def self.connect_to_base
    begin
      client = BaseCRM::Client.new(
        access_token: Setting.plugin_basecrm[:base_token]
      )
    rescue
      return { error: l(:client_error) }
    end

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
    loss_reasons = []

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
      when 'loss_reason'
        loss_reasons.push(resource)
      else
        meta.sync.ack
      end
    end

    {
      deals: deals,
      resources: resources,
      notes: notes,
      sources: sources,
      stages: stages,
      loss_reasons: loss_reasons
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
    return if options[:stages][deal.stage_id] =~ /poten/i

    issue_id = Deal.find_issue_id(deal.id)

    if issue_id.present?
      Deal.update_issue(deal, issue_id, options)
    else
      issue_id = Deal.create_issue(deal, options[:resources])
    end

    Deal.check_stage(deal.stage_id, issue_id, options[:stages])
  end

  def self.create_issue(deal, resources)
    author_id = Deal.assign_to(Deal.user_name(deal.owner_id, resources))
    issue = Issue.new(
      tracker_id: Setting.plugin_basecrm[:tracker_id],
      project_id: Setting.plugin_basecrm[:main_project_id],
      priority: IssuePriority.find_by_position_name('default'),
      subject: deal.name.to_s,
      description: Deal.description(deal, resources),
      author_id: author_id || User.current.id,
      assigned_to_id: author_id
    )

    if issue.save
      IssueRevision.create_revision(issue.id, deal)
      Deal.update_custom_fields(issue, deal.id, deal.value)
    end

    issue.id
  end

  def self.update_issue(deal, issue_id, options)
    issue = Issue.find(issue_id)
    deal_notes = Deal.find_notes(deal.id, options[:notes])
    deal_notes.each do |note|
      issue.touch if Deal.create_note(issue_id, note, options[:resources])
    end

    Deal.update_issue_fields(issue, deal, options[:resources])

    diff = IssueRevision.differences(deal, issue_id)
    if diff.any? && (k = diff.keys - REDUNDANT_KEYS).any?
      # changing only contact somehow change last_stage_change_at so we prevent updating whole issue
      return if k.length == 1 && k.first == :last_stage_change_at
      note = IssueRevision.note(deal.creator_id, deal.updated_at, diff, options)
      issue.touch if IssueRevision.create_note(issue_id, note)
      IssueRevision.create_revision(issue_id, deal)
    end
  end

  def self.check_stage(stage_id, issue_id, stages)
    issue = Issue.find(issue_id)
    case stages[stage_id]
    when /Won|Wygrane/i
      issue.update_attributes(
        category_id: Setting.plugin_basecrm[:category_id],
        project_id: Setting.plugin_basecrm[:next_stage_project_id]
      )
    when /Closure|Zamkni/i
      issue.update_attributes(
        project_id: Setting.plugin_basecrm[:next_stage_project_id]
      )
    when /Lost|Unquali|Niezakwali|Utrac/i
      issue.update_attributes(
        status_id: IssueStatus.where(is_closed: true).first.id,
        closed_on: DateTime.now
      )
    end
    Deal.reopen_issue(issue, stages[stage_id]) unless issue.closed_on.nil?
  end

  def self.reopen_issue(issue, stage)
    if stage =~ /Incom|^Quali|Quote|Closure|Won|Wygrane|Zamkni/i
      issue.update_attributes(
        status_id: IssueStatus.where(is_default: true).first.id,
        closed_on: nil
      )
    end
  end

  def self.description(deal, resources)
    items = []

    link = "https://app.futuresimple.com/sales/deals/#{deal.id}"

    items << "Contact Name: #{Deal.contact_name(deal.contact_id, resources)}" unless deal.contact_id.nil?
    items << "Company Name: #{Deal.contact_name(deal.organization_id, resources)}" unless deal.organization_id.nil?
    items << "User name: #{Deal.user_name(deal.owner_id, resources)}"
    items << "Link: #{link}"

    Setting.plugin_basecrm[:html_tags] ? items.join('<br />') : items.join("\r\n")
  end

  def self.create_note(issue_id, note, resources)
    author_id = Deal.assign_to(Deal.user_name(note.creator_id, resources))
    note = Deal.note(note, resources)
    unless Deal.note_exists?(issue_id, note)
      j = Journal.new(
        journalized_id: issue_id,
        journalized_type: 'Issue',
        user_id: author_id || User.current.id,
        notes: note
      )
      j.save
    else
      false
    end
  end

  def self.note(note, resources)
    items = []

    items << "Deal edited by: #{Deal.user_name(note.creator_id, resources)}"
    items << "Deal edited at: #{Time.parse(note.created_at).in_time_zone('Warsaw')}"
    items << 'Note was added to deal. Content:'
    items << "<blockquote>#{note.content}</blockquote>"

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

  def self.find_issue_id(deal_id)
    cf_id = CustomField.find { |cf| cf.name =~ /did/i }.try(:id)
    CustomValue.find { |cv| cv.custom_field_id == cf_id && cv.value == deal_id.to_s }
               .try(:customized_id)
  end

  def self.find_notes(deal_id, notes)
    deal_notes = []
    notes.each do |note|
      deal_notes.push(note) if note.resource_id == deal_id
    end
    deal_notes
  end

  def self.note_exists?(issue_id, note)
    journals = Journal.where(journalized_type: 'Issue', journalized_id: issue_id)
    journals.each do |journal|
      return true if journal.notes == note
    end
    false
  end

  def self.update_issue_fields(issue, deal, resources)
    Deal.update_custom_fields(issue, deal.id, deal.value)
    issue.update_attributes(
      assigned_to_id: Deal.assign_to(Deal.user_name(deal.owner_id, resources))
    ) if deal.owner_id.present?
    issue.update_attributes(
      subject: deal.name.to_s
    ) if deal.name.present?
  end

  def self.update_custom_fields(issue, deal_id, deal_value)
    if (custom_field = issue.custom_field_values.find { |cfv| cfv.custom_field.name =~ /did/i })
      custom_field.value = deal_id
      issue.save
    end

    if (custom_field = issue.custom_field_values.find { |cfv| cfv.custom_field.name =~ /budget/i })
      custom_field.value = deal_value
      issue.save
    end
  end

  def self.loss_reason(loss_reason_id, loss_reasons)
    loss_reasons.each do |reason|
      return reason.name if reason.id == loss_reason_id
    end
    nil
  end
end
