require 'tests/issue_extension.rb'

Redmine::Plugin.register :basecrm do
  name 'Basecrm plugin'
  author 'Szczepan'
  description 'This is a plugin for Redmine'
  version '0.0.1'
  url 'http://1000i.pl'
  author_url 'http://1000i.pl'

  menu :top_menu, :basecrm, {controller: :tests, action: :show}, caption: :basecrm

  project_module :basecrm do
    permission :tests, {tests: :show}
  end
end
