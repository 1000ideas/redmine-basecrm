class TestsController < ApplicationController
  unloadable

  def show
    @my_issues = Issue.assigned_to_current_user
  end

end
