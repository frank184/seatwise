module Customers
  class IssueSignInCode
    CODE_LIFETIME = 10.minutes
    RESEND_COOLDOWN = 60.seconds
    CODE_DIGITS = 6

    class ResendTooSoon < StandardError
    end

    def self.call(email:)
      normalized_email = email.to_s.strip.downcase
      customer = Customer.find_or_create_by!(email: normalized_email)
      code = format("%0#{CODE_DIGITS}d", SecureRandom.random_number(10**CODE_DIGITS))

      customer.with_lock do
        if customer.sign_in_code_sent_at && customer.sign_in_code_sent_at > RESEND_COOLDOWN.ago
          raise ResendTooSoon
        end

        customer.update!(
          sign_in_code_digest: SignInCodeDigest.call(code),
          sign_in_code_expires_at: CODE_LIFETIME.from_now,
          sign_in_code_sent_at: Time.current,
          sign_in_code_attempts: 0
        )
      end

      [customer, code]
    end
  end
end
