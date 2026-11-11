require "application_system_test_case"

module Portal
  class ReservationCheckoutTest < ApplicationSystemTestCase
    setup do
      @event = events(:one)
      visit "/events/#{@event.id}"
      assert_text @event.name
      install_stripe_stubs
    end

    test "loads the provider and renders card payment when no wallet is eligible" do
      begin_checkout(wait_for_payment: false)

      assert_equal false, page.evaluate_script("'defaultValues' in window.__checkoutElementsOptions")
      assert_text "Loading payment options"
      assert_selector "button[data-payment-submit]:not([disabled])"
      assert_selector "[data-payment-element]"
      assert_text "No accelerated payment methods are available"
      assert_text "Row A · seats 4"
      assert_text /4:5\d remaining/
      assert_selector "[data-held-seat='1:4']"
      assert_no_selector "[data-payment-provider='paypal']"
    end

    test "card payment confirms with Stripe without submitting card details to Seatwise" do
      begin_checkout
      click_button "Pay securely"

      assert_selector "[data-flow-stage='redirecting']:not([hidden])"
      assert_text "Waiting for payment confirmation"
      assert_no_selector "[data-flow-stage='confirmed']:not([hidden])"
      page.execute_script("window.__checkoutStatus = 'succeeded'")
      assert_selector "[data-flow-stage='confirmed']:not([hidden])"
      assert_selector "[data-booking-step='4'].step-success"
      assert_selector "[data-held-seat='1:4']"
      assert_equal 1, page.evaluate_script("window.__stripeConfirmCalls")
      assert_no_selector "input[name='card_number']"
    end

    test "Express Checkout wallet confirmation uses the same Stripe confirmation path" do
      begin_checkout
      page.execute_script("window.__expressCheckoutConfirm()")

      assert_selector "[data-flow-stage='redirecting']:not([hidden])"
      assert_equal 1, page.evaluate_script("window.__stripeConfirmCalls")
    end

    test "restores a Stripe return and confirms only after server reconciliation" do
      begin_checkout
      page.execute_script(<<~JS)
        window.__checkoutStatus = "succeeded";
        const url = new URL(window.location.href);
        url.searchParams.set("reservation_id", "987");
        url.searchParams.set("session_id", "cs_test_987");
        history.replaceState({}, "", url.toString());
        const root = document.querySelector("[data-event-show]");
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "portal--reservation");
        controller.flow.reservation.expiresAt = Date.now() - 1000;
        controller.restoreCheckoutReturn("cs_test_987");
      JS

      assert_selector "[data-flow-stage='confirmed']:not([hidden])"
      assert_selector "[data-booking-step='4'].step-success"
      assert_selector "[data-held-seat='1:4']"
    end

    test "retries payment setup after a mounted Element reports a load error" do
      begin_checkout
      page.execute_script("window.__paymentLoadError()")
      assert_selector "button[data-payment-retry]:not([hidden])"
      click_button "Retry payment setup"

      assert_selector "button[data-payment-submit]:not([disabled])"
      assert_equal 2, page.evaluate_script("window.__loadActionsCalls")
      assert_selector "[data-payment-element][data-mounted-element='payment']"
    end

    test "disabled provider configuration leaves payment unavailable and keeps the hold visible" do
      install_stripe_stubs(provider_enabled: false)
      begin_checkout(wait_for_payment: false)

      assert_text "Online payment is temporarily unavailable"
      assert_selector "button[data-payment-submit][disabled]"
      assert_text "Row A · seats 4"
      assert_selector "[data-held-seat='1:4']"
    end

    private

    def begin_checkout(wait_for_payment: true)
      find("button[data-seat='1'][data-row='1']").click
      click_button "Review seats"
      fill_in "Email for your booking", with: "alex@example.com"
      click_button "Continue to payment"
      assert_selector "[data-flow-stage='payment']:not([hidden])"
      assert_selector "button[data-payment-submit]:not([disabled])" if wait_for_payment
    end

    def install_stripe_stubs(provider_enabled: true)
      page.execute_script(<<~JS)
        window.__stripeConfirmCalls = 0;
        window.__loadActionsCalls = 0;
        window.__checkoutElementsOptions = null;
        window.__checkoutStatus = "processing";
        window.__expressCheckoutConfirm = null;
        window.__paymentLoadError = null;
        const originalFetch = window.fetch.bind(window);
        window.fetch = async (input, init = {}) => {
          const url = new URL(typeof input === "string" ? input : input.url, window.location.href);
          if (url.pathname === "/api/v1/reservations" && init.method === "POST") {
            window.__holdPayload = JSON.parse(init.body);
            return new Response(JSON.stringify({ id: 987, event_id: #{@event.id}, row_id: 1,
              seat_start: 4, seat_end: 4, status: "held", expires_at: new Date(Date.now() + 300000).toISOString() }),
              { status: 201, headers: { "Content-Type": "application/json" } });
          }
          if (url.pathname === "/api/v1/organizations/development") {
            return new Promise((resolve) => setTimeout(() => resolve(new Response(JSON.stringify({ data: { id: "development", payment_provider: {
              id: "dev-stripe", provider_key: "stripe", enabled: #{provider_enabled}, publishable_key: "pk_test_stub" } } }),
              { status: 200, headers: { "Content-Type": "application/json" } })), 300));
          }
          if (url.pathname === "/api/v1/reservations/987/checkout/session") {
            return new Response(JSON.stringify({ data: { payment_id: 1, session_id: "cs_test_987", client_secret: "cs_test_987_secret_stub",
              amount: 1000, currency: "cad", status: "pending" } }),
              { status: 201, headers: { "Content-Type": "application/json" } });
          }
          if (url.pathname === "/api/v1/reservations/987/checkout") {
            const status = window.__checkoutStatus;
            return new Response(JSON.stringify({ status, reservation: { id: 987,
              status: status === "succeeded" ? "confirmed" : "held" } }),
              { status: 200, headers: { "Content-Type": "application/json" } });
          }
          if (url.pathname === "/api/v1/reservations/987" && init.method === "DELETE") {
            return new Response(JSON.stringify({ data: { id: 987, status: "cancelled" } }),
              { status: 200, headers: { "Content-Type": "application/json" } });
          }
          return originalFetch(input, init);
        };
        window.Stripe = () => ({
          initCheckoutElementsSdk: (options) => {
            window.__checkoutElementsOptions = options;
            return ({
              loadActions: async () => { window.__loadActionsCalls += 1; return ({ type: "success", actions: {
                confirm: async () => { window.__stripeConfirmCalls += 1; return { type: "success" }; },
              } }); },
              createExpressCheckoutElement: () => ({
                mount: (target) => {
                  target.dataset.mountedElement = "expressCheckout";
                },
                on: (name, callback) => {
                  if (name === "ready") callback({ availablePaymentMethods: null });
                  if (name === "confirm") window.__expressCheckoutConfirm = callback;
                },
              }),
              createPaymentElement: () => ({
                on: (name, callback) => { if (name === "loaderror") window.__paymentLoadError = callback; },
                mount: (target) => {
                  target.dataset.mountedElement = "payment";
                  target.textContent = "Card payment form";
                },
              }),
            });
          },
        });
      JS
    end
  end
end
