require "test_helper"

module Portal
  class SignInsControllerTest < ActionDispatch::IntegrationTest
    setup { Portal::SignInsController::RATE_LIMIT_STORE.clear }

    test "sign-in form includes a CSRF token" do
      old_forgery_protection = Portal::SignInsController.allow_forgery_protection
      Portal::SignInsController.allow_forgery_protection = true
      get sign_in_path

      assert_response :success
      assert_select "form[action='#{sign_in_code_path}'] input[name='authenticity_token']"
      assert_select "input[type=email][name='sign_in[email]'][required]"
    ensure
      Portal::SignInsController.allow_forgery_protection = old_forgery_protection
    end

    test "rejects a code request without a valid CSRF token" do
      old_forgery_protection = Portal::SignInsController.allow_forgery_protection
      Portal::SignInsController.allow_forgery_protection = true

      post sign_in_code_path, params: { sign_in: { email: "buyer@example.test" } }

      assert_response :unprocessable_entity
      assert_nil Customer.find_by(email: "buyer@example.test")
    ensure
      Portal::SignInsController.allow_forgery_protection = old_forgery_protection
    end

    test "known and unknown email requests return the same generic response shape" do
      responses =
        [customers(:one).email, "first.booking@example.test"].map do |email|
          post sign_in_code_path, params: { sign_in: { email: } }
          assert_redirected_to sign_in_verify_path
          follow_redirect!
          assert_response :success
          assert_select ".alert p",
                        text: "If that email can sign in, a one-time code will arrive shortly."
          "If that email can sign in, a one-time code will arrive shortly."
        end

      assert_equal responses.first, responses.second
      assert_equal "first.booking@example.test",
                   Customer.find_by!(email: "first.booking@example.test").email
      assert_nil Customer.find_by!(email: "first.booking@example.test").email_verified_at
    end

    test "invalid OTP does not establish an authenticated customer session" do
      request_code_for("first.booking@example.test")
      customer = Customer.find_by!(email: "first.booking@example.test")

      post sign_in_verify_path, params: { sign_in: { code: "bad-code" } }

      assert_response :unprocessable_entity
      assert_nil session[:customer_id]
      assert_equal customer.id, session[:pending_customer_id]
      assert_nil customer.reload.email_verified_at
    end

    test "verified OTP rotates the Rails session and ignores a submitted customer id" do
      request_code_for(customers(:one).email)
      pending_customer = customers(:one)
      code = delivered_code
      old_session_cookie = cookies["_seatwise_session"]

      post sign_in_verify_path, params: { sign_in: { code:, customer_id: customers(:two).id } }

      assert_redirected_to root_path
      assert_equal pending_customer.id, session[:customer_id]
      assert_nil session[:pending_customer_id]
      assert_not_equal old_session_cookie, cookies["_seatwise_session"]
      assert_not_nil pending_customer.reload.email_verified_at
    end

    test "preserves a local OAuth return path and rejects an external return path" do
      request_code_for(
        customers(:one).email,
        return_to: "/oauth/authorize?client_id=portal&state=abc"
      )
      post sign_in_verify_path, params: { sign_in: { code: delivered_code } }

      assert_redirected_to "/oauth/authorize?client_id=portal&state=abc"

      reset!
      request_code_for("another@example.test", return_to: "https://attacker.example/phish")
      post sign_in_verify_path, params: { sign_in: { code: delivered_code } }

      assert_redirected_to root_path
    end

    test "preserves the ticket email return path to reservation management" do
      request_code_for(customers(:one).email, return_to: "/account/reservations")

      post sign_in_verify_path, params: { sign_in: { code: delivered_code } }

      assert_redirected_to account_reservations_path
      assert_equal customers(:one).id, session[:customer_id]
    end

    test "verification customer comes only from the pre-auth session" do
      request_code_for(customers(:one).email)
      post sign_in_verify_path,
           params: {
             sign_in: {
               code: delivered_code,
               customer_id: customers(:two).id
             }
           }

      assert_equal customers(:one).id, session[:customer_id]
      assert_not_equal customers(:two).id, session[:customer_id]
    end

    test "OTP success rotates the guest capability and preserves its active holds" do
      bootstrap_guest_cart
      old_secret = cookies[:guest_cart]
      cart = GuestCart.resolve(old_secret)
      reservation =
        Reservation.create!(
          event: events(:one),
          customer: customers(:two),
          guest_cart: cart,
          row_id: 50,
          seat_range: 1...3,
          status: :held,
          hold_expires_at: 5.minutes.from_now
        )
      request_code_for(customers(:one).email)

      post sign_in_verify_path, params: { sign_in: { code: delivered_code } }

      new_secret = cookies[:guest_cart]
      assert_not_equal old_secret, new_secret
      assert_nil GuestCart.resolve(old_secret)
      assert_equal cart.id, GuestCart.resolve(new_secret).id
      assert_equal cart.id, reservation.reload.guest_cart_id
      assert reservation.held?
    end

    test "sign-out clears the customer session but retains the guest cart" do
      bootstrap_guest_cart
      request_code_for(customers(:one).email)
      post sign_in_verify_path, params: { sign_in: { code: delivered_code } }
      guest_secret = cookies[:guest_cart]
      assert_equal customers(:one).id, session[:customer_id]

      post sign_out_path

      assert_redirected_to root_path
      assert_nil session[:customer_id]
      new_guest_secret = cookies[:guest_cart]
      assert_not_equal guest_secret, new_guest_secret
      assert_nil GuestCart.resolve(guest_secret)
      assert GuestCart.resolve(new_guest_secret).present?
    end

    test "rate limits code requests by normalized email and remote IP" do
      5.times do
        post sign_in_code_path,
             params: {
               sign_in: {
                 email: "  limit@example.test "
               }
             },
             headers: {
               "REMOTE_ADDR" => "192.0.2.98"
             }
        assert_redirected_to sign_in_verify_path
      end
      post sign_in_code_path,
           params: {
             sign_in: {
               email: "LIMIT@example.test"
             }
           },
           headers: {
             "REMOTE_ADDR" => "192.0.2.98"
           }
      assert_response :too_many_requests

      reset!
      20.times do |index|
        post sign_in_code_path,
             params: {
               sign_in: {
                 email: "limit-#{index}@example.test"
               }
             },
             headers: {
               "REMOTE_ADDR" => "192.0.2.99"
             }
      end
      post sign_in_code_path,
           params: {
             sign_in: {
               email: "another-limit@example.test"
             }
           },
           headers: {
             "REMOTE_ADDR" => "192.0.2.99"
           }
      assert_response :too_many_requests
    end

    private

    def request_code_for(email, return_to: nil)
      params = { sign_in: { email: } }
      params[:return_to] = return_to if return_to
      post sign_in_code_path, params: params
      assert_redirected_to sign_in_verify_path
      follow_redirect!
    end

    def delivered_code
      ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
    end

    def bootstrap_guest_cart
      post api_v1_guest_sessions_path,
           params: {
             transport: "cookie"
           },
           headers: {
             "Origin" => Rails.application.config.x.portal_origin
           },
           as: :json
      assert_response :created
    end
  end
end
