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
    all_res = []

    sync.fetch do |meta, resource|
      all_res.push(resource)
      if meta.type.to_s == 'deal'
        deals.push(resource)
        meta.sync.ack
      elsif BASE_TYPES.include? meta.type.to_s
        resources.push(resource)
      end
    end

    { deals: deals, resources: resources }
  end

  def self.create_or_update_ticket(deal, resources)
    tickets = Deal.tickets_from_base

    if Deal.already_exists?(tickets, deal.id.to_s)
      Deal.update_ticket(deal, tickets)
    else
      Deal.create_ticket(deal, resources)
    end
  end

  def self.create_ticket(deal, resources)
    issue = Issue.new(
      tracker_id: Setting.plugin_basecrm[:tracker_id],
      project_id: Setting.plugin_basecrm[:project_id],
      priority: IssuePriority.find_by_position_name('default'),
      subject: "DID: #{deal.id} - #{deal.name}",
      description: Deal.description(deal, resources),
      author: User.find(1),
      assigned_to_id: Deal.assign_to(Deal.user_name(deal.owner_id, resources))
    )

    issue.save
  end

  def self.update_ticket(deal, tickets)
    ticket_id = 0
    tickets.each do |issue|
      if issue['subject'] == deal.id.to_s
        ticket_id = issue['id'].to_i
        break
      end
    end

    j = Journal.new(
      journalized_id: ticket_id,
      journalized_type: 'Issue',
      user_id: User.current.id,
      notes: 'Zmiana na BaseCRM',
      created_on: Time.now
    )

    Issue.find(ticket_id).touch

    j.save
  end

  def self.description(deal, resources)
    items = []

    link = "https://app.futuresimple.com/sales/deals/#{deal.id}"

    # items << "#{l(:contact_name)}: #{Deal.contact_name(deal.contact_id, resources)}" unless deal.contact_id.nil?
    # items << "#{l(:organization_name)}: #{Deal.contact_name(deal.organization_id, resources)}" unless deal.organization_id.nil?
    # items << "#{l(:user_name)}: #{Deal.user_name(deal.owner_id, resources)}"
    # items << "#{l(:scope)}: #{deal.value} #{deal.currency}"
    # items << "#{l(:link_to_base)}: #{link}"

    items << "Contact Name: #{Deal.contact_name(deal.contact_id, resources)}" unless deal.contact_id.nil?
    items << "Company Name: #{Deal.contact_name(deal.organization_id, resources)}" unless deal.organization_id.nil?
    items << "User name: #{Deal.user_name(deal.owner_id, resources)}"
    items << "Scope: #{deal.value} #{deal.currency}"
    items << "Link: #{link}"

    items.join("\n\n")
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

  def self.already_exists?(tickets, deal_id)
    tickets.each do |ticket|
      return true if ticket['subject'] == deal_id
    end
    false
  end

  def self.tickets_from_base
    tickets = []
    Issue.connection.select_all(Issue.select('id, subject')).each do |issue|
      t = Deal.id_from_ticket(issue['subject'])
      if t.present?
        issue['subject'] = t
        tickets.push(issue)
      end
    end
    tickets
  end
end
