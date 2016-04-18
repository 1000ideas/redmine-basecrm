include ActionView::Helpers::TextHelper
require 'basecrm'

class DealsController < ApplicationController
  unloadable

  skip_before_filter :check_if_login_required
  skip_before_filter :verify_authenticity_token

  accept_api_auth :check_for_new_deals

  def check_for_new_deals
    options = Deal.connect_to_base

    if options.include? :error
      redirect_to(home_path, flash: { error: options[:error] }) and return
    elsif options[:deals].any?
      options[:deals].each do |deal|
        Deal.create_or_update_ticket(deal, options[:resources])
      end
    end

    redirect_to home_path
  end
end
