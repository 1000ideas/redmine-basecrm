Redmine::Plugin.register :basecrm do
  name 'Basecrm plugin'
  author '1000ideas'
  description 'This plugin allows you to get deals from BaseCRM as soon as they appear'
  version '0.0.1'
  url 'http://1000i.pl'
  author_url 'http://1000i.pl'

  menu :top_menu,
       :basecrm,
       { controller: :deals, action: :check_for_new_deals },
       caption: :top_menu_deals

  project_module :basecrm do
    permission :deals, deals: :check_for_new_deals
  end

  settings default: { 'tracker_id' => Tracker.first.id, 'project_id' => Project.first.id },
           partial: 'deals/settings'
end
