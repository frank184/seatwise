class Customer < ApplicationRecord
  has_many :reservations
  has_many :payments, through: :reservations
  validates_presence_of :email, :sign_in_code_attempts
  validates_uniqueness_of :email
end
