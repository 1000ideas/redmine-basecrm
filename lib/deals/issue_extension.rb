require 'basecrm'

# access token for base-crm
# 5dd38d5b675c56f9651b42ff66dde2d74971d0490c6af94aa66cf3e87b47b801
module IssueBasecrmExtension
  extend ActiveSupport::Concern

  included do
    # before_filter :require_admin_or_api_request, :create_new_ticket
    # accept_api_auth :create_new_ticket

    scope :assigned_to_current_user,
          -> { where(assigned_to_id: User.current.id) }

    BASE_TYPES = ['user', 'contact']

    def self.check_if_new_deal_exists
      client = BaseCRM::Client.new(access_token:
        '5dd38d5b675c56f9651b42ff66dde2d74971d0490c6af94aa66cf3e87b47b801')
      sync = BaseCRM::Sync.new(client: client, device_uuid: 'my_uuid38')

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

      binding.pry

      { deals: deals, resources: resources }
    end

    def self.create_new_ticket(deal, resources)
      desc = []
      desc << "Contact Name: #{Deal.contact_name(deal.contact_id, resources)}"
      desc << "Company Name: #{Deal.contact_name(deal.contact_id, resources, true)}"
      desc << "User Name: #{Deal.user_name(deal.owner_id, resources)}"
      desc << "Scope: #{deal.value} #{deal.currency}"

      issue = Issue.new(
        tracker: Tracker.first,
        project: Project.first,
        priority: Enumeration.where(name: 'Normal', type: 'IssuePriority').first,
        subject: "DID: #{deal.id} - #{deal.name}",
        description: desc.join('\n'),
        author: User.find(1)
      )

      if issue.save
        @deal_created = 'Stworzono umowe!'
      else
        
      end
    end
  end
end

Issue.send :include, IssueBasecrmExtension
