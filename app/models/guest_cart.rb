require "digest"
require "securerandom"

class GuestCart < ApplicationRecord
  LIFETIME = 30.days
  TRANSPORTS = %w[cookie body].freeze

  has_many :reservations, dependent: :nullify

  validates :secret_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where("expires_at > ?", Time.current) }

  def self.issue!(transport:)
    unless TRANSPORTS.include?(transport.to_s)
      raise ArgumentError, "unsupported guest-cart transport"
    end

    secret = SecureRandom.urlsafe_base64(32)
    cart = create!(secret_digest: digest(secret), expires_at: LIFETIME.from_now)
    [cart, secret]
  end

  def self.resolve(secret)
    return if secret.blank?

    active.find_by(secret_digest: digest(secret))
  end

  def self.cleanup_expired!(now: Time.current)
    where("expires_at <= ?", now).delete_all
  end

  def self.digest(secret)
    Digest::SHA256.hexdigest(secret)
  end

  def rotate_secret!
    secret = SecureRandom.urlsafe_base64(32)
    update!(secret_digest: self.class.digest(secret))
    secret
  end
end
