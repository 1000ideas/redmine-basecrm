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

    def self.check_if_new_deal_exists
      client = BaseCRM::Client.new(access_token:
        '5dd38d5b675c56f9651b42ff66dde2d74971d0490c6af94aa66cf3e87b47b801')
      sync = BaseCRM::Sync.new(client: client, device_uuid: 'my_uuid19')

      deals = []

      sync.fetch do |meta, resource|
        deals.push(resource) if meta.type == 'deal'
        meta.sync.ack
      end

      deals
    end

    def self.create_new_ticket(deal)
      issue = Issue.new(
        tracker: Tracker.first,
        project: Project.first,
        subject: deal.name,
        description: '',
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
