Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get "up", to: "health#show", as: :health
      resources :events, only: %i[index show]
      resources :reservations, only: %i[create]
    end
  end

  # Rails process health; API health lives under the versioned API namespace.
  get "up" => "rails/health#show", :as => :rails_health_check

  scope module: :portal do
    root "events#index"
    resources :events, only: %i[index show]
    get "design", to: "design_system#show", as: :design_system
    get "status", to: "status#show", as: :status
  end
end
