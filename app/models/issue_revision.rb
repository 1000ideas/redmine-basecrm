class IssueRevision < ActiveRecord::Base
  unloadable

  belongs_to :issue, foreign_key: 'issue_id'

  ## deal.instance_values["table"] is a Hash with info about Deal
  def self.create_revision(issue_id, deal)
    rev_num = where(issue_id: issue_id).pluck(:revision_id).last || 0
    revision = new(
      issue_id: issue_id,
      revision_id: rev_num + 1,
      deal_info: deal.instance_values['table'].to_json
    )

    revision.save
  end

  def self.last_deal_revision(issue_id)
    deal_info = where(issue_id: issue_id).pluck('deal_info').last
    return nil if deal_info.nil?
    h = JSON.parse(deal_info).symbolize_keys
    h[:associated_contacts].symbolize_keys!
    h[:associated_contacts][:meta].symbolize_keys!
    h
  end

  def self.differences(deal, issue_id)
    last_rev = last_deal_revision(issue_id)
    deal.instance_values['table'].diff(last_rev)
  end

  def self.create_note(issue_id, note)
    j = Journal.new(
      journalized_id: issue_id,
      journalized_type: 'Issue',
      user_id: User.current.id,
      notes: note
    )

    j.save
  end

  def self.note(creator_id, updated_at, diff, options)
    items = []

    items << 'Deal was changed on BaseCRM'
    items << "Deal edited by: #{Deal.user_name(creator_id, options[:resources])}"
    items << "Deal edited at: #{Time.parse(updated_at).in_time_zone('Warsaw')}"
    items << IssueRevision.note_details(diff, options).flatten

    Setting.plugin_basecrm[:html_tags] ? items.join('<br />') : items.join("\r\n")
  end

  def self.note_details(diff, options)
    items = []

    items << IssueRevision.name_info(diff[:name])
    items << IssueRevision.value_info(diff[:value])
    items << IssueRevision.currency_info(diff[:currency])
    items << IssueRevision.stage_info(diff[:stage_id], options[:stages])
    items << IssueRevision.stage_change_at_info(diff[:last_stage_change_at])
    items << IssueRevision.stage_change_by_info(diff[:last_stage_change_by_id], options[:resources])
    items << IssueRevision.source_info(diff[:source_id], options[:sources])
    items << IssueRevision.hot_info(diff[:is_hot])
    items << IssueRevision.estimated_close_date_info(diff[:estimated_close_date])
    items << IssueRevision.tags_info(diff[:tags])

    items.compact
  end

  def self.name_info(name)
    return nil if name.nil?
    "Name was changed to: #{name}"
  end

  def self.value_info(value)
    return nil if value.nil?
    "Value was changed to: #{value}"
  end

  def self.currency_info(currency)
    return nil if currency.nil?
    "Currency was changed to: #{currency}"
  end

  def self.stage_info(stage_id, stages)
    return nil if stage_id.nil?
    "Stage was changed to: #{stages[stage_id]}"
  end

  def self.stage_change_at_info(last_change_at)
    return nil if last_change_at.nil?
    "Stage was changed at: #{Time.parse(last_change_at).in_time_zone('Warsaw')}"
  end

  def self.stage_change_by_info(last_change_by, resources)
    return nil if last_change_by.nil?
    "Stage was changed by: #{Deal.user_name(last_change_by, resources)}"
  end

  def self.source_info(source_id, sources)
    return nil if source_id.nil?
    "Source was changed to: #{sources[source_id]}"
  end

  def self.hot_info(is_hot)
    return nil if is_hot.nil?
    return 'Deal was marked as hot' if is_hot
    return 'Deal was marked as not hot' unless is_hot
    nil
  end

  def self.estimated_close_date_info(date)
    return nil if date.nil?
    "Estimated close date was changed to: #{Date.parse(date)}"
  end

  def self.tags_info(tags)
    return nil if tags.nil?
    "Tags that were added: #{tags.join(', ')}"
  end
end
