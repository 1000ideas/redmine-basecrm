Redmine::Plugin.register :basecrm do
  name 'BaseCRM plugin'
  author '1000ideas'
  description 'Get your deals from BaseCRM as soon as they appear'
  version '0.0.1'
  url 'http://1000i.pl'
  author_url 'http://1000i.pl'

  settings default: { 'tracker_id' => Tracker.first.id,
                      'main_project_id' => Project.first.id,
                      'next_stage_project_id' => Project.first.id,
                      'omit_project_id' => Project.first.id,
                      'category_id' => nil,
                      'html_tags' => true,
                      'base_token' => '',
                      'device_uuid' => '' },
           partial: 'deals/settings'
end
