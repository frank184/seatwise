module Customers
  class VerifySignInCode
    MAX_ATTEMPTS = 5

    def self.call(customer:, code:)
      verified = false

      customer.with_lock do
        next if customer.sign_in_code_digest.blank?

        if customer.sign_in_code_expires_at.blank? || customer.sign_in_code_expires_at <= Time.current
          clear_code(customer)
          next
        end

        next if customer.sign_in_code_attempts >= MAX_ATTEMPTS

        if valid_code?(customer.sign_in_code_digest, code)
          customer.update!(
            email_verified_at: customer.email_verified_at || Time.current,
            sign_in_code_digest: nil,
            sign_in_code_expires_at: nil,
            sign_in_code_sent_at: nil,
            sign_in_code_attempts: 0
          )
          verified = true
        else
          attempts = customer.sign_in_code_attempts + 1
          attributes = { sign_in_code_attempts: attempts }
          attributes.merge!(sign_in_code_digest: nil, sign_in_code_expires_at: nil) if attempts >= MAX_ATTEMPTS
          customer.update!(attributes)
        end
      end

      verified
    end

    def self.valid_code?(digest, code)
      return false unless code.is_a?(String) && code.match?(/\A\d{6}\z/)

      ActiveSupport::SecurityUtils.secure_compare(digest, SignInCodeDigest.call(code))
    end
    private_class_method :valid_code?

    def self.clear_code(customer)
      customer.update!(sign_in_code_digest: nil, sign_in_code_expires_at: nil)
    end
    private_class_method :clear_code
  end
end
