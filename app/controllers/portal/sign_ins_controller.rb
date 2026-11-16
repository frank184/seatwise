require "uri"

module Portal
  class SignInsController < ApplicationController
    layout "portal"
    protect_from_forgery with: :exception

    PENDING_CUSTOMER_SESSION_KEY = :pending_customer_id
    RETURN_TO_SESSION_KEY = :oauth_return_to
    RATE_LIMIT_STORE = Rails.env.test? ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

    rate_limit to: 20,
                within: 15.minutes,
                by: -> { request.remote_ip },
                store: RATE_LIMIT_STORE,
                name: "sign_in_code_by_ip",
                only: :create,
                with: -> { render_rate_limit }
    rate_limit to: 5,
                within: 15.minutes,
                by: -> { normalized_email },
                store: RATE_LIMIT_STORE,
                name: "sign_in_code_by_email",
                only: :create,
                with: -> { render_rate_limit }

    def new
      @return_to = safe_return_path(params[:return_to])
    end

    def create
      email = normalized_email
      return_to = safe_return_path(params[:return_to]) || safe_return_path(session[RETURN_TO_SESSION_KEY])

      if email.blank? || !email.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
        clear_pending_sign_in
        flash[:notice] = generic_request_message
        return redirect_to sign_in_path(return_to:)
      end

      begin
        customer, code = Customers::IssueSignInCode.call(email:)
        CustomerMailer.sign_in_code(customer, code).deliver_now
      rescue Customers::IssueSignInCode::ResendTooSoon
        customer = Customer.find_by(email:)
      end

      if customer
        session[PENDING_CUSTOMER_SESSION_KEY] = customer.id
        session[RETURN_TO_SESSION_KEY] = return_to if return_to
      else
        clear_pending_sign_in
      end

      flash[:notice] = generic_request_message
      redirect_to sign_in_verify_path
    end

    def verify
      @customer = pending_customer
      return redirect_to sign_in_path unless @customer

      @return_to = safe_return_path(session[RETURN_TO_SESSION_KEY])
    end

    def verify_code
      customer = pending_customer
      return redirect_to sign_in_path unless customer

      if Customers::VerifySignInCode.call(customer:, code: sign_in_params[:code].to_s)
        finish_sign_in(customer)
      else
        @customer = customer
        @return_to = safe_return_path(session[RETURN_TO_SESSION_KEY])
        @verification_error = true
        render :verify, status: :unprocessable_entity
      end
    end

    def destroy
      cart = GuestCart.resolve(cookies[:guest_cart])
      rotated_guest_secret = cart&.rotate_secret!
      reset_session
      write_guest_cart_cookie(cart, rotated_guest_secret) if cart && rotated_guest_secret
      redirect_to root_path, status: :see_other
    end

    private

    def sign_in_params
      params.fetch(:sign_in, ActionController::Parameters.new).permit(:email, :code)
    end

    def normalized_email
      sign_in_params[:email].to_s.strip.downcase
    end

    def pending_customer
      Customer.find_by(id: session[PENDING_CUSTOMER_SESSION_KEY])
    end

    def clear_pending_sign_in
      session.delete(PENDING_CUSTOMER_SESSION_KEY)
      session.delete(RETURN_TO_SESSION_KEY)
    end

    def safe_return_path(candidate)
      return unless candidate.is_a?(String) && candidate.start_with?("/")
      return if candidate.start_with?("//", "/\\") || candidate.include?("\\") || candidate.match?(/[\u0000-\u001f\u007f]/)

      uri = URI.parse(candidate)
      return unless uri.scheme.nil? && uri.host.nil? && uri.userinfo.nil?
      return unless uri.path.in?(%w[/oauth/authorize /account/reservations])

      candidate
    rescue URI::InvalidURIError
      nil
    end

    def finish_sign_in(customer)
      return_to = safe_return_path(session[RETURN_TO_SESSION_KEY])
      cart = GuestCart.resolve(cookies[:guest_cart])
      rotated_guest_secret = cart&.rotate_secret!

      reset_session
      session[:customer_id] = customer.id
      session[RETURN_TO_SESSION_KEY] = return_to if return_to
      write_guest_cart_cookie(cart, rotated_guest_secret) if cart && rotated_guest_secret

      redirect_to return_to.presence || root_path, status: :see_other
    end

    def write_guest_cart_cookie(cart, secret)
      cookies[:guest_cart] = {
        value: secret,
        expires: cart.expires_at,
        path: "/",
        httponly: true,
        same_site: :lax,
        secure: Rails.env.production?
      }
    end

    def generic_request_message
      "If that email can sign in, a one-time code will arrive shortly."
    end

    def render_rate_limit
      @return_to = safe_return_path(params[:return_to])
      flash.now[:notice] = generic_request_message
      render :new, status: :too_many_requests
    end
  end
end
