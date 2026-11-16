Rails.application.routes.draw do
  use_doorkeeper do
    skip_controllers :applications, :authorized_applications, :token_info
  end
  mount ActionCable.server => "/cable"

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  namespace :api do
    namespace :v1 do
      get "up", to: "health#show", as: :health
      resources :events, only: %i[index show]
      post "guest_sessions", to: "guest_sessions#create", as: :guest_sessions
      resources :reservations, only: %i[index show create destroy]
      get "organizations/:id", to: "organizations#show", as: :organization
      post "reservations/:reservation_id/checkout/session",
           to: "checkouts#create",
           as: :checkout_session
      get "reservations/:reservation_id/checkout", to: "checkouts#show", as: :checkout_status
      post "reservations/:reservation_id/checkout/reconcile",
           to: "checkouts#reconcile",
           as: :checkout_reconcile
      post "payment_webhooks/stripe", to: "stripe_webhooks#create", as: :stripe_webhook
    end
  end

  # Rails process health; API health lives under the versioned API namespace.
  get "up" => "rails/health#show", :as => :rails_health_check

  scope module: :portal do
    root "events#index"
    resources :events, only: %i[index show]
    get "sign-in", to: "sign_ins#new", as: :sign_in
    post "sign-in/code", to: "sign_ins#create", as: :sign_in_code
    get "sign-in/verify", to: "sign_ins#verify", as: :sign_in_verify
    post "sign-in/verify", to: "sign_ins#verify_code", as: :verify_sign_in_code
    post "sign-out", to: "sign_ins#destroy", as: :sign_out
    get "oauth/start", to: "oauth_clients#start", as: :oauth_start
    get "oauth/callback", to: "oauth_clients#callback", as: :oauth_callback
    get "account/reservations", to: "oauth_clients#reservations", as: :account_reservations
    get "design", to: "design_system#show", as: :design_system
    get "status", to: "status#show", as: :status
  end
end
