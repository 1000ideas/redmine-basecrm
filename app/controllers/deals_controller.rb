include ActionView::Helpers::TextHelper

class DealsController < ApplicationController
  unloadable

  def check_for_new_deals
    options = Issue.check_if_new_deal_exists
    successes = []

    if options.any?
      options.each do |deal|
        successes.push(Issue.create_new_ticket(deal))
      end
    end

    redirect_to home_path, notice: "Created #{ pluralize(successes.count, 'deal') }"
  end
end
