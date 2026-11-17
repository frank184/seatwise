require "digest"
require "securerandom"

class Guest < ApplicationRecord
  LIFETIME = 30.days
  has_many :reservations, dependent: :nullify

  validates :secret_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where("expires_at > ?", Time.current) }

  def self.issue!
    token = SecureRandom.urlsafe_base64(32)
    guest = create!(secret_digest: digest(token), expires_at: LIFETIME.from_now)
    [guest, token]
  end

  def self.resolve(token)
    return if token.blank?

    active.find_by(secret_digest: digest(token))
  end

  def self.cleanup_expired!(now: Time.current)
    where("expires_at <= ?", now).delete_all
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token)
  end
end
