Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  namespace :api do
    namespace :v1 do
      get "up", to: "health#show", as: :health
      resources :events, only: %i[index show]
      resources :reservations, only: %i[create destroy]
      get "organizations/:id", to: "organizations#show", as: :organization
      post "reservations/:reservation_id/checkout/session",
           to: "checkouts#create",
           as: :checkout_session
      get "reservations/:reservation_id/checkout", to: "checkouts#show", as: :checkout_status
      post "payment_webhooks/stripe", to: "stripe_webhooks#create", as: :stripe_webhook
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
