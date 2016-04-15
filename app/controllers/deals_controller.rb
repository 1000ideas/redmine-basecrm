include ActionView::Helpers::TextHelper
require 'basecrm'

class DealsController < ApplicationController
  unloadable

  skip_before_filter :check_if_login_required
  skip_before_filter :verify_authenticity_token

  accept_api_auth :check_for_new_deals

  def check_for_new_deals
    options = Deal.connect_to_base
    successes = []

    if options.include? :error
      redirect_to home_path, error: options[:error] and return
    elsif options[:deals].any?
      options[:deals].each do |deal|
        successes.push(Deal.create_new_ticket(deal, options[:resources]))
      end
    end

    redirect_to home_path, notice:
      "#{l(:tickets_created)}: #{successes.count(true)}"
  end
end
