namespace :basecrm do
  desc 'Rewrite issues subjects and put DID in custom field'
  task rewrite_subjects: [:environment] do
    issues = Issue.where('subject REGEXP ?', '^\s?DID: ')

    issues.each do |issue|
      deal_info = deal_subject(issue.subject)
      if (custom_field = issue.custom_field_values.find { |cfv| cfv.custom_field.name =~ /did/i })
        custom_field.value = deal_info.first
      end
      issue.update_attributes(subject: deal_info.last)
    end
  end

  def deal_subject(subject)
    values = subject.split(' ')
    did = values[1]
    values.shift(3)
    [did, values.join(' ')]
  end
end
