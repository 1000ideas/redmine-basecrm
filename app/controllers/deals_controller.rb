class DealsController < ApplicationController
  unloadable

  def show
    @my_issues = Issue.assigned_to_current_user
    @options = @my_issues.first.create_new_ticket
  end

end
