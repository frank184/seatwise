require "application_system_test_case"

module Portal
  class OauthClientTest < ApplicationSystemTestCase
    setup { @previous_portal_origin = Rails.application.config.x.portal_origin }

    teardown { Rails.application.config.x.portal_origin = @previous_portal_origin }

    test "Portal completes PKCE sign-in and calls the private reservations API" do
      create_portal_client

      visit account_reservations_path
      assert_selector "form[action='#{sign_in_code_path}']", wait: 10
      sign_in_uri = URI.parse(page.current_url)
      assert_equal sign_in_path, sign_in_uri.path
      pending_authorization = Rack::Utils.parse_nested_query(sign_in_uri.query).fetch("return_to")
      pending_authorization_uri = URI.parse(pending_authorization)
      assert_equal "/oauth/authorize", pending_authorization_uri.path
      assert_nil pending_authorization_uri.host

      fill_in "Email address", with: "one@example.test"
      click_button "Email me a code"
      assert_current_path sign_in_verify_path
      code = ActionMailer::Base.deliveries.last.text_part.body.to_s[/\b\d{6}\b/]
      assert code.present?
      find("input[aria-label='Six-digit verification code']").set(code)
      click_button "Verify and continue"

      assert_oauth_navigation_to(account_reservations_path)
      assert_text "Reservation #{reservations(:one).id}", wait: 10
      assert_text "row 1, seats 1–1"
      token_json = page.evaluate_script("sessionStorage.getItem('seatwise.oauth.token')")
      assert token_json.present?, "OAuth callback should persist an access token in this tab"
      assert_match(/Bearer/, token_json)
      access_token = JSON.parse(token_json).fetch("access_token")
      transaction = page.evaluate_script("sessionStorage.getItem('seatwise.oauth.transaction')")
      assert_nil transaction

      helper_result = page.evaluate_async_script(<<~JS)
        const done = arguments[0];
        import("controllers/portal/view_helpers").then(({ fetchJson }) =>
          fetchJson("/api/v1/reservations", { headers: { "X-Portal-Test": "kept" } })
            .then((reservations) => done({ ids: reservations.map((reservation) => reservation.id) }))
            .catch((error) => done({ error: error.message }))
        );
      JS
      assert_nil helper_result["error"],
                 "Portal API helper should return the authenticated reservation list"
      assert helper_result["ids"].present?,
             "Portal API helper should return at least one reservation ID"
      assert_includes helper_result.fetch("ids"), reservations(:one).id

      expired_token = JSON.parse(token_json)
      expired_token["expires_at"] = 1
      page.execute_script(
        "sessionStorage.setItem('seatwise.oauth.token', arguments[0])",
        JSON.generate(expired_token)
      )
      delivered_email_count = ActionMailer::Base.deliveries.size
      visit account_reservations_path
      assert_oauth_navigation_to(account_reservations_path)
      assert_text "Reservation #{reservations(:one).id}", wait: 10
      assert_equal delivered_email_count, ActionMailer::Base.deliveries.size
      renewed_token =
        JSON.parse(page.evaluate_script("sessionStorage.getItem('seatwise.oauth.token')"))
      assert_operator renewed_token.fetch("expires_at"), :>, (Time.current.to_f * 1000).to_i
      access_token = renewed_token.fetch("access_token")

      visit oauth_start_path(return_to: "/events?when=upcoming")
      click_button "Continue with Seatwise"
      assert_oauth_navigation_to("/events?when=upcoming")
      assert_text "Find your event"

      # Sign-out revokes the token currently stored by this authorization, which
      # is distinct from the earlier token renewed after expiry.
      access_token =
        JSON.parse(page.evaluate_script("sessionStorage.getItem('seatwise.oauth.token')")).fetch(
          "access_token"
        )
      page.execute_script(<<~JS)
        const originalFetch = window.fetch.bind(window);
        window.fetch = async (...args) => {
          const response = await originalFetch(...args);
          if (String(args[0]).includes("/oauth/revoke")) {
            sessionStorage.setItem("seatwise.oauth.revoke_status", String(response.status));
          }
          return response;
        };
      JS

      find("summary[aria-label='Reservation options']").click
      click_button "Sign out"
      assert_current_path root_path, wait: 10
      assert_nil page.evaluate_script("sessionStorage.getItem('seatwise.oauth.token')")
      revoke_status = page.evaluate_script("sessionStorage.getItem('seatwise.oauth.revoke_status')")
      assert_equal "200",
                   revoke_status,
                   "Sign-out should successfully call Doorkeeper's OAuth revocation endpoint"
      persisted_token =
        Doorkeeper::AccessToken.find_by!(token: Digest::SHA256.hexdigest(access_token))
      assert persisted_token.revoked?, "Sign-out should revoke the current tab's access token"
    end

    test "OAuth return path accepts local paths and rejects scheme-relative hosts" do
      create_portal_client

      visit oauth_start_path(return_to: "/events?when=upcoming")
      continue_button = find("button[data-controller='portal--oauth']")
      assert_equal "/events?when=upcoming", continue_button["data-return-to"]

      visit oauth_start_path(return_to: "//attacker.example/collect")
      continue_button = find("button[data-controller='portal--oauth']")
      assert_equal account_reservations_path, continue_button["data-return-to"]
      assert_no_text "attacker.example"
    end

    private

    def create_portal_client
      visit root_path
      portal_origin = URI.parse(page.current_url).origin
      Rails.application.config.x.portal_origin = portal_origin

      Doorkeeper::Application.create!(
        name: "Seatwise Portal",
        redirect_uri: "#{portal_origin}/oauth/callback",
        scopes: "reservations:read reservations:manage",
        confidential: false,
        secret: nil
      )
    end

    def assert_oauth_navigation_to(expected_path)
      assert_current_path expected_path, wait: 20
    rescue Minitest::Assertion => assertion
      status =
        (
          if page.has_css?("#oauth-client-status", wait: 1)
            page.find("#oauth-client-status").text
          else
            nil
          end
        )
      body_excerpt = page.body.to_s.gsub(/\s+/, " ").first(1_000)
      browser_errors =
        begin
          page.driver.browser.manage.logs.get(:browser).map(&:message)
        rescue StandardError => error
          ["Browser console unavailable: #{error.message}"]
        end
      flunk(
        "Expected OAuth navigation to #{expected_path.inspect}; current URL=#{page.current_url.inspect}; " \
          "callback status=#{status.inspect}; page body=#{body_excerpt.inspect}; " \
          "browser console=#{browser_errors.inspect}; " \
          "path assertion=#{assertion.message}"
      )
    end
  end
end
