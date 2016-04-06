require 'basecrm'

# access token for base-crm
# 5dd38d5b675c56f9651b42ff66dde2d74971d0490c6af94aa66cf3e87b47b801
module IssueBasecrmExtension
  extend ActiveSupport::Concern

  included do
    # before_filter :require_admin_or_api_request, :create_new_ticket
    # accept_api_auth :create_new_ticket

    scope :assigned_to_current_user, -> { where(assigned_to_id: User.current.id) }
  end

  def create_new_ticket
    client = BaseCRM::Client.new(access_token:
      '5dd38d5b675c56f9651b42ff66dde2d74971d0490c6af94aa66cf3e87b47b801')
    sync = BaseCRM::Sync.new(client: client, device_uuid: "my_uuid14")
   
    options = []

    sync.fetch do |meta, resource|
      if meta.type == "deal"
        options.push({
          table: meta.type,
          statement: meta.sync.event_type,
          properties: resource
        })

        meta.sync.ack
      end
    end

    options.each do |option|
      Issue.create(subject: option[:properties].name, project_id: 1)
    end

    options
  end
end

Issue.send :include, IssueBasecrmExtension
