class Customer < ApplicationRecord
  has_many :reservations
  has_many :payments, through: :reservations

  before_validation :normalize_email

  validates_presence_of :email, :sign_in_code_attempts
  validates_uniqueness_of :email

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
