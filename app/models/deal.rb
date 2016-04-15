class Deal < ActiveRecord::Base
  unloadable

  BASE_TYPES = %w(user contact).freeze

  def self.connect_to_base
    begin
      client = BaseCRM::Client.new(access_token:
        Setting.plugin_basecrm[:base_token])
    rescue
      return { error: l(:client_error) }
    end
    # '5dd38d5b675c56f9651b42ff66dde2d74971d0490c6af94aa66cf3e87b47b801')
    begin
      sync = BaseCRM::Sync.new(client: client,
                               device_uuid: Setting.plugin_basecrm[:device_uuid])
    rescue
      return { error: l(:sync_error) }
    end

    Deal.sync_data(sync)
  end

  def self.sync_data(sync)
    resources = []
    deals = []

    sync.fetch do |meta, resource|
      if meta.type.to_s == 'deal'
        deals.push(resource)
      elsif BASE_TYPES.include? meta.type.to_s
        resources.push(resource)
      end

      meta.sync.ack
    end

    { deals: deals, resources: resources }
  end

  def self.create_new_ticket(deal, resources)
    issue = Issue.new(
      tracker_id: Setting.plugin_basecrm[:tracker_id],
      project_id: Setting.plugin_basecrm[:project_id],
      priority: Enumeration.where(name: 'Normal', type: 'IssuePriority').first,
      subject: "DID: #{deal.id} - #{deal.name}",
      description: Deal.description(deal, resources),
      author: User.find(1),
      assigned_to_id: Deal.assign_to(Deal.user_name(deal.owner_id, resources))
    )

    issue.save ? true : false
  end

  def self.description(deal, resources)
    items = []

    link = "https://app.futuresimple.com/sales/deals/#{deal.id}"

    items << "#{l(:contact_name)}: #{Deal.contact_name(deal.contact_id, resources)}" unless deal.contact_id.nil?
    items << "#{l(:organization_name)}: #{Deal.contact_name(deal.organization_id, resources, true)}" unless deal.organization_id.nil?
    items << "#{l(:user_name)}: #{Deal.user_name(deal.owner_id, resources)}"
    items << "#{l(:scope)}: #{deal.value} #{deal.currency}"
    items << "#{l(:link_to_base)}: #{link}"

    items.join("\n\n")
  end

  def self.contact_name(id, resources, organization = false)
    resources.each do |resource|
      return resource.name if resource.id == id &&
                              resource.is_organization == organization
    end
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
end
