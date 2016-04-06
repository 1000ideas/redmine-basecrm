module IssueBasecrmExtension
  extend ActiveSupport::Concern

  included do
    scope :assigned_to_current_user, lambda { where(assigned_to_id: User.current.id) }
  end

  def create_new_ticket
    "Stoworzono nowy ticket dla '#{subject}'"
  end
end

Issue.send :include, IssueBasecrmExtension