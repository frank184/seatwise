Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get "up", to: "health#show", as: :health
    end
  end

  # Rails process health; API health lives under the versioned API namespace.
  get "up" => "rails/health#show", as: :rails_health_check
end
