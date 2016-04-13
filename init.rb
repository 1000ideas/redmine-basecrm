Redmine::Plugin.register :basecrm do
  name 'Basecrm plugin'
  author '1000ideas'
  description 'This plugin allows you to get deals from BaseCRM as soon as they appear'
  version '0.0.1'
  url 'http://1000i.pl'
  author_url 'http://1000i.pl'

  settings default: { 'tracker_id' => Tracker.first.id, 'project_id' => Project.first.id },
           partial: 'deals/settings'
end
