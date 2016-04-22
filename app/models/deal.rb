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
    pipeline = {}

    sync.fetch do |meta, resource|
      if meta.type.to_s == 'deal'
        deals.push(resource)
        meta.sync.ack
      elsif BASE_TYPES.include? meta.type.to_s
        resources.push(resource)
      elsif meta.type.to_s == 'pipeline'
        pipeline = Deal.pipeline_stages(resource)
      elsif meta.type.to_s == 'note'
        notes.push(resource)
        meta.sync.ack
      else
        meta.sync.ack
      end
    end

    { deals: deals, resources: resources, notes: notes, pipeline: pipeline }
  end

  def self.pipeline_stages(resource)
    pipeline = {}
    resource.stages[:items].each do |item|
      pipeline[item[:data][:name]] = item[:data][:id]
    end
    pipeline
  end

  def self.create_or_update_ticket(deal, resources, notes, pipeline)
    ticket = Deal.ticket_from_base(deal.id.to_s)

    if ticket.present?
      Deal.update_ticket(deal, resources, ticket, notes)
    else
      ticket = {}
      ticket['id'] = Deal.create_ticket(deal, resources)
    end

    if deal.stage_id == pipeline['Won']
      Issue.find(ticket['id'])
           .update_attribute(:category_id, Setting.plugin_basecrm[:category_id])
    end
  end

  def self.create_ticket(deal, resources)
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

    if issue.save
      return issue.id
    end
  end

  def self.update_ticket(deal, resources, ticket, notes)
    if Deal.find_note(deal.id, notes)
      j = Journal.new(
        journalized_id: ticket['id'],
        journalized_type: 'Issue',
        user_id: User.current.id,
        notes: Deal.note(deal, resources, notes),
        created_on: deal.created_at
      )

      j.save

      Issue.find(ticket['id']).touch
    end
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

  def self.note(deal, resources, notes)
    items = []

    if notes.any?
      deal_note = Deal.find_note(deal.id, notes)
      items << "Deal edited by: #{Deal.user_name(deal_note.creator_id, resources)}"
      items << "Deal edited at: #{deal_note.created_at}"
      items << 'Content:'
      items << deal_note.content
    else
      items << "Deal edited by: #{Deal.user_name(deal.creator_id, resources)}"
      items << "Deal edited at: #{deal.created_at}"
      items << 'Deal was changed on BaseCRM'
    end

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
  end

  def self.assign_to(full_name)
    names = full_name.split(' ')
    assignee = User.where(firstname: names[0], lastname: names[1]).first
    return assignee.id unless assignee.nil?
  end

  def self.id_from_ticket(subject)
    arr = subject.split(' ')
    arr[0] == 'DID:' ? arr[1] : nil
  end

  def self.ticket_from_base(deal_id)
    issues = []
    Issue.connection.select_all(Issue.select('id, subject')).each do |issue|
      t = Deal.id_from_ticket(issue['subject'])
      issues.push(issue) if t.present? && t == deal_id
    end
    issues.last
  end

  def self.find_note(deal_id, notes)
    notes.each do |t|
      return t if t.resource_id == deal_id
    end
    nil
  end
end
