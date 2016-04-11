# resource :deals, only: [:new]

get 'deals' => 'deals#check_for_new_deals'

root :to => 'welcome#index', :as => 'home'
