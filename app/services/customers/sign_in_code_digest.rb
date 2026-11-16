module Customers
  module SignInCodeDigest
    def self.call(code)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, code)
    end
  end
end
