class StripeWebhookEvent < ApplicationRecord
  validates :external_id, :event_type, presence: true
end
