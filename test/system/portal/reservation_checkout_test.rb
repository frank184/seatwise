require "application_system_test_case"

module Portal
  class ReservationCheckoutTest < ApplicationSystemTestCase
    setup do
      @event = events(:one)
      normalized_test_name = name.downcase.tr(" -", "_")
      @defer_availability_fallback = normalized_test_name.include?("initial_fallback")
      if normalized_test_name.include?("subscription_confirmation") ||
          normalized_test_name.include?("initial_fallback") ||
          normalized_test_name.include?("in_flight_snapshot_across_expiry") ||
          normalized_test_name.include?("in_flight_invalidation") ||
          normalized_test_name.include?("removes_unavailable_selection") ||
          normalized_test_name.include?("availability_summary") ||
          normalized_test_name.include?("cancel_refresh_failure") ||
          normalized_test_name.include?("another_reservation") ||
          normalized_test_name.include?("seat_map_selection") ||
          normalized_test_name.include?("seat_map_drag")
        install_availability_preload
      end
      visit "/events/#{@event.id}"
      assert_text @event.name unless @availability_preload_identifier
      install_stripe_stubs
    end

    teardown do
      page.execute_script("Date.now = window.__seatwiseAvailabilityHarness.originalDateNow") if @restore_date_now
      if @availability_preload_identifier
        page.driver.browser.execute_cdp(
          "Page.removeScriptToEvaluateOnNewDocument",
          identifier: @availability_preload_identifier
        )
      end
    end

    test "waits for availability subscription confirmation before fetching the event snapshot" do
      assert_selector "html[data-availability-subscription='#{@event.id}']"
      assert_equal 0, availability_event_request_count

      page.execute_script("window.__seatwiseAvailabilityHarness.changeBeforeFirstSnapshot = true")

      confirm_availability_subscription

      assert_selector "#event-content:not([hidden])"
      assert_text @event.name
      assert_equal 1, availability_event_request_count
      changed_seat = page.evaluate_script("window.__seatwiseAvailabilityHarness.changedSeat")
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='#{changed_seat}'][aria-label*='held or reserved']"
    end

    test "uses a bounded initial snapshot fallback and refreshes again when subscription connects" do
      assert_selector "html[data-availability-subscription='#{@event.id}']"
      assert_equal 0, availability_event_request_count

      page.execute_script(<<~JS)
        window.__seatwiseAvailabilityHarness.runInitialFallback();
      JS

      assert_selector "#event-content:not([hidden])"
      assert_equal 1, availability_event_request_count
      seat = page.evaluate_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        const row = harness.lastSnapshot.rows.find((item) => String(item.row_id) === "1");
        const seatNumber = Array.from({ length: row.seat_count }, (_, index) => index + 1)
          .find((number) => !row.reserved_seats.includes(number));
        harness.nextReservedSeat = seatNumber;
        seatNumber;
      JS

      page.execute_script("window.__seatwiseAvailabilityHarness.callbacks.connected()")

      assert_selector "html[data-availability-event-requests='2']"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='#{seat}'][aria-label*='held or reserved']"
      assert_equal 2, availability_event_request_count
    end

    test "keeps the six-seat selection limit in the reservation coordinator" do
      confirm_availability_subscription
      assert_selector "#event-content:not([hidden])"
      open_seats = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll("[data-detail-rows] button[data-seat]:not([disabled])"))
          .slice(0, 7)
          .map((seat) => ({ row: seat.dataset.row, number: seat.dataset.seat }))
      JS
      assert_equal 7, open_seats.length

      open_seats.each do |seat|
        row = seat.fetch("row")
        number = seat.fetch("number")
        page.execute_script(
          "document.querySelector(\"[data-detail-rows] button[data-row='#{row}'][data-seat='#{number}']\").click()",
        )
      end

      assert_text "6 of 6 seats selected"
      assert_text "You can select up to 6 seats."
      assert_equal 6, page.evaluate_script(
        "window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-event-show]'), 'portal--reservation').selectedSeats.size",
      )
    end

    test "keeps seat nodes stable while dragging and clicking another seat" do
      confirm_availability_subscription
      assert_selector "#event-content:not([hidden])"
      seats = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll("[data-detail-rows] button[data-seat]:not([disabled])"))
          .slice(0, 3)
          .map((seat) => ({ row: seat.dataset.row, number: seat.dataset.seat }))
      JS
      assert_equal 3, seats.length

      page.execute_script(<<~JS)
        const [first, second, third] = #{seats.to_json};
        const lookup = ({ row, number }) =>
          document.querySelector(`[data-detail-rows] button[data-row='${row}'][data-seat='${number}']`);
        const firstSeat = lookup(first);
        const secondSeat = lookup(second);
        const thirdSeat = lookup(third);
        window.__seatMapDragNodes = { firstSeat, secondSeat, thirdSeat };
        firstSeat.dispatchEvent(new PointerEvent("pointerdown", {
          bubbles: true, button: 0, pointerId: 1, pointerType: "mouse",
        }));
        secondSeat.dispatchEvent(new PointerEvent("pointerenter", {
          bubbles: true, button: 0, pointerId: 1, pointerType: "mouse",
        }));
        window.dispatchEvent(new PointerEvent("pointerup", {
          bubbles: true, button: 0, pointerId: 1, pointerType: "mouse",
        }));
        firstSeat.dispatchEvent(new MouseEvent("click", { bubbles: true, detail: 1 }));
        lookup(third).dispatchEvent(new MouseEvent("click", { bubbles: true, detail: 1 }));
        window.__seatMapDragNodesPreserved =
          lookup(first) === firstSeat && lookup(second) === secondSeat && lookup(third) === thirdSeat;
      JS

      assert_equal true, page.evaluate_script("window.__seatMapDragNodesPreserved")
      assert_equal 3, page.evaluate_script(
        "window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-event-show]'), 'portal--reservation').selectedSeats.size",
      )
    end

    test "ignores an in-flight snapshot across expiry and applies one trailing fresh snapshot" do
      assert_selector "html[data-availability-subscription='#{@event.id}']"
      assert_equal 0, availability_event_request_count

      confirm_availability_subscription
      assert_selector "#event-content:not([hidden])"
      assert_equal 1, availability_event_request_count
      begin_checkout

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        const root = document.querySelector("[data-event-show]");
        const reservationController = window.Stimulus.getControllerForElementAndIdentifier(
          root, "portal--reservation"
        );
        clearInterval(reservationController.holdTimer);
        const deadline = Date.now() + 30000;
        reservationController.flow.reservation.expiresAt = deadline;
        harness.deadline = deadline;
        harness.deferNext = true;
        root.dispatchEvent(new CustomEvent("portal--reservation:refresh-availability", { bubbles: true }));
      JS
      assert_equal 2, availability_event_request_count

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        const root = document.querySelector("[data-event-show]");
        const reservationController = window.Stimulus.getControllerForElementAndIdentifier(
          root, "portal--reservation"
        );
        harness.deferNext = true;
        harness.originalDateNow = Date.now;
        Date.now = () => harness.deadline + 1;
        reservationController.updateCountdown();
      JS
      @restore_date_now = true

      assert_equal(
        { "step" => "payment", "status" => "held" },
        page.evaluate_script(<<~JS)
          const root = document.querySelector("[data-event-show]");
          const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "portal--reservation");
          ({ step: controller.flow.step, status: controller.flow.reservation.status })
        JS
      )
      assert_selector "[data-detail-rows][aria-busy='true']"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][data-held-seat='1:4']"
      assert_selector "[data-flow-stage='payment']:not([hidden])"
      assert_equal 2, availability_event_request_count

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        harness.resolveNext(harness.snapshotWithReservedSeat(2));
      JS
      assert_selector "html[data-availability-event-requests='3']"
      assert_equal 3, availability_event_request_count
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='2'][aria-label$='open']"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][data-held-seat='1:4']"
      assert_selector "[data-detail-rows][aria-busy='true']"
      assert_equal 1, page.evaluate_script("window.__seatwiseAvailabilityHarness.pending.length")

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        harness.resolveNext(harness.snapshotWithReservedSeat(4));
      JS

      assert_selector "[data-flow-stage='expired']:not([hidden])"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][aria-label*='held or reserved']"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='2'][aria-label$='open']"
      assert_no_selector "[data-detail-rows][aria-busy='true']"
      assert_equal 3, availability_event_request_count
      assert_equal 0, page.evaluate_script("window.__availabilityDeleteCalls || 0")
      assert_equal "expired", page.evaluate_script(<<~JS)
        const root = document.querySelector("[data-event-show]");
        window.Stimulus.getControllerForElementAndIdentifier(root, "portal--reservation").flow.reservation.status
      JS

      page.execute_script(
        "document.querySelector(\"[data-detail-rows] button[data-row='1'][data-seat='2']\").click()",
      )
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='2'][aria-label$='selected'][aria-pressed='true']"
      assert_selector "button[data-selection-review]:not([disabled])"
      click_button "Review seats"
      assert_selector "[data-flow-stage='email']:not([hidden])"
    end

    test "keeps the current map busy until one trailing snapshot follows an in-flight invalidation" do
      assert_selector "html[data-availability-subscription='#{@event.id}']"
      confirm_availability_subscription
      assert_selector "#event-content:not([hidden])"

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        harness.deferNext = true;
        harness.callbacks.received({ type: "availability_changed" });
      JS
      assert_equal 2, availability_event_request_count
      assert_selector "[data-detail-rows][aria-busy='true']"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][aria-label$='open']"

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        harness.deferNext = true;
        harness.callbacks.received({ type: "availability_changed" });
      JS
      assert_equal 2, availability_event_request_count

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        harness.resolveNext(harness.snapshotWithReservedSeat(4));
      JS
      assert_selector "html[data-availability-event-requests='3']"
      assert_equal 3, availability_event_request_count
      assert_selector "[data-detail-rows][aria-busy='true']"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][aria-label$='open']"
      assert_equal 1, page.evaluate_script("window.__seatwiseAvailabilityHarness.pending.length")

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        harness.resolveNext(harness.snapshotWithReservedSeat(5));
      JS
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='5'][aria-label*='held or reserved']"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][aria-label$='open']"
      assert_no_selector "[data-detail-rows][aria-busy='true']"
      assert_equal 3, availability_event_request_count
    end

    test "clears a failed hold idempotency key when a fresh snapshot removes unavailable selection" do
      confirm_availability_subscription
      assert_selector "#event-content:not([hidden])"

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        const root = document.querySelector("[data-event-show]");
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "portal--reservation");
        const row = controller.event.rows.find((item) => String(item.row_id) === "1");
        const number = Array.from({ length: row.seat_count }, (_, index) => index + 1)
          .find((seatNumber) => !row.reserved_seats.includes(seatNumber));
        const key = controller.seatKey(row.row_id, number);
        controller.selectedSeats.add(key);
        controller.flow.request = { status: "failed", idempotencyKey: "old-request-key" };
        const snapshot = structuredClone(harness.lastSnapshot);
        harness.reserveSeat(snapshot, number);
        controller.applyAvailabilitySnapshot({ detail: { event: snapshot } });
        window.__removedSelectionResult = {
          key,
          idempotencyKey: controller.flow.request.idempotencyKey,
          selected: controller.selectedSeats.has(key),
          seatNumber: number,
        };
      JS

      result = page.evaluate_script("window.__removedSelectionResult")
      assert_nil result.fetch("idempotencyKey")
      assert_equal false, result.fetch("selected")
      assert_selector "[data-detail-rows] button[data-seat='#{result.fetch("seatNumber")}'][aria-label*='held or reserved']"
    end

    test "keeps the availability summary correct when the canonical snapshot includes the guest's hold" do
      confirm_availability_subscription
      assert_selector "#event-content:not([hidden])"
      begin_checkout

      displayed_availability = page.evaluate_script("Number(document.querySelector('[data-detail-open]').textContent.match(/\\d+/)[0])")
      assert_equal page.evaluate_script("window.__seatwiseAvailabilityHarness.lastSnapshot.available_count - 1"), displayed_availability

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        harness.nextReservedSeat = 4;
        harness.callbacks.received({ type: "availability_changed" });
      JS
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][data-held-seat='1:4']"

      canonical_availability = page.evaluate_script("window.__seatwiseAvailabilityHarness.lastSnapshot.available_count")
      displayed_availability = page.evaluate_script("Number(document.querySelector('[data-detail-open]').textContent.match(/\\d+/)[0])")
      assert_equal canonical_availability, displayed_availability
      assert_equal canonical_availability, page.evaluate_script("window.Stimulus.getControllerForElementAndIdentifier(document.querySelector('[data-event-show]'), 'portal--reservation').event.available_count")
    end

    test "keeps seats disabled after cancel refresh failure until retry applies a fresh snapshot" do
      confirm_availability_subscription
      assert_selector "#event-content:not([hidden])"
      begin_checkout

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        harness.failNext = true;
      JS
      click_button "Cancel hold"
      click_button "Release hold and choose seats"

      assert_selector "#event-error:not([hidden])"
      assert_equal 1, page.evaluate_script("window.__availabilityDeleteCalls")
      assert_selector "[data-detail-rows][aria-busy='true']"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][data-held-seat='1:4'][disabled]"

      page.execute_script("window.__seatwiseAvailabilityHarness.deferNext = true")
      click_button "Retry"
      assert_equal 3, availability_event_request_count
      assert_selector "#event-error:not([hidden])"
      assert_selector "[data-detail-rows][aria-busy='true']"

      page.execute_script("window.__seatwiseAvailabilityHarness.resolveNext(window.__seatwiseAvailabilityHarness.lastSnapshot)")
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][aria-label$='open']"
      assert_no_selector "#event-error:not([hidden])"
      assert_no_selector "[data-detail-rows][aria-busy='true']"

      page.execute_script(<<~JS)
        const harness = window.__seatwiseAvailabilityHarness;
        const root = document.querySelector("[data-event-show]");
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "portal--reservation");
        harness.failNext = true;
        controller.startAgain();
      JS

      assert_selector "#event-error:not([hidden])"
      assert_selector "[data-detail-rows][aria-busy='true']"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][aria-label$='open'][disabled]"

      page.execute_script("window.__seatwiseAvailabilityHarness.deferNext = true")
      click_button "Retry"
      assert_equal 5, availability_event_request_count
      assert_selector "#event-error:not([hidden])"
      assert_selector "[data-detail-rows][aria-busy='true']"

      page.execute_script("window.__seatwiseAvailabilityHarness.resolveNext(window.__seatwiseAvailabilityHarness.lastSnapshot)")
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][aria-label$='open']"
      assert_no_selector "#event-error:not([hidden])"
      assert_no_selector "[data-detail-rows][aria-busy='true']"
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

    test "keeps checkout Elements mounted only on the payment stage" do
      begin_checkout
      assert_selector "[data-payment-element][data-mounted-element='payment']"

      click_button "Email & hold"

      assert_selector "[data-flow-stage='email']:not([hidden])"
      assert_no_selector "[data-payment-element][data-mounted-element='payment']"
      click_button "Payment"
      assert_selector "[data-flow-stage='payment']:not([hidden])"
      assert_selector "[data-payment-element][data-mounted-element='payment']"
    end

    test "does not create duplicate Stripe sessions for concurrent setup requests" do
      begin_checkout(wait_for_payment: false)
      page.execute_script(<<~JS)
        const root = document.querySelector("[data-event-show]");
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "portal--reservation");
        Promise.all([controller.loadCheckout(), controller.loadCheckout()]);
      JS

      assert_selector "button[data-payment-submit]:not([disabled])"
      assert_equal 1, page.evaluate_script("window.__checkoutSessionCalls")
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

    test "starting another reservation keeps confirmed seats in the refreshed inventory" do
      confirm_availability_subscription
      assert_selector "#event-content:not([hidden])"
      begin_checkout
      page.execute_script("window.__seatwiseAvailabilityHarness.nextReservedSeat = 4")
      click_button "Pay securely"
      page.execute_script("window.__checkoutStatus = 'succeeded'")

      assert_selector "[data-flow-stage='confirmed']:not([hidden])"
      assert_selector "html[data-availability-event-requests='2']"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][aria-label*='held or reserved']"

      click_button "Start another reservation"

      assert_selector "html[data-availability-event-requests='3']"
      assert_selector "#checkout-panel[hidden]"
      assert_selector "[data-detail-rows] button[data-row='1'][data-seat='4'][aria-label*='held or reserved']"
      assert_equal true, page.evaluate_script(<<~JS)
        window.__seatwiseAvailabilityHarness.lastSnapshot.rows
          .find((row) => String(row.row_id) === "1").reserved_seats.includes(4)
      JS
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

    test "shows recovery guidance when a Stripe return cannot restore the browser reservation" do
      begin_checkout
      page.execute_script(<<~JS)
        const url = new URL(window.location.href);
        url.searchParams.set("reservation_id", "missing");
        url.searchParams.set("session_id", "cs_test_missing");
        history.replaceState({}, "", url.toString());
        const root = document.querySelector("[data-event-show]");
        const controller = window.Stimulus.getControllerForElementAndIdentifier(root, "portal--reservation");
        controller.flow.reservation = null;
        controller.restoreCheckoutReturn("cs_test_missing");
      JS

      assert_selector "[data-flow-stage='redirecting']:not([hidden])"
      assert_text "We couldn’t restore this reservation in your browser. Check your booking email for an update."
    end

    test "retries payment setup after a mounted Element reports a load error" do
      begin_checkout
      page.execute_script("window.__paymentLoadError()")
      assert_selector "button[data-payment-retry]:not([hidden])"
      page.execute_script(<<~JS)
        const root = document.querySelector("[data-event-show]");
        window.Stimulus.getControllerForElementAndIdentifier(root, "portal--reservation").renderFlow();
      JS
      assert_selector "button[data-payment-submit][disabled]"
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

    def install_availability_preload
      source = <<~JS
        (() => {
          const harness = {
            deferInitialFallback: #{@defer_availability_fallback ? "true" : "false"},
            callbacks: null,
            deadline: null,
            deferNext: false,
            failNext: false,
            changeBeforeFirstSnapshot: false,
            changedSeat: null,
            nextReservedSeat: null,
            eventRequests: 0,
            pending: [],
            lastSnapshot: null,
          };
          if (harness.deferInitialFallback) {
            const nativeSetTimeout = window.setTimeout.bind(window);
            const nativeClearTimeout = window.clearTimeout.bind(window);
            window.setTimeout = (callback, delay, ...args) => {
              if (delay === 2000) {
                harness.initialFallbackCallback = callback;
                return 2000002;
              }
              return nativeSetTimeout(callback, delay, ...args);
            };
            window.clearTimeout = (timerId) => {
              if (timerId === 2000002) {
                harness.initialFallbackCallback = null;
                return;
              }
              nativeClearTimeout(timerId);
            };
            harness.runInitialFallback = () => {
              const callback = harness.initialFallbackCallback;
              harness.initialFallbackCallback = null;
              if (!callback) throw new Error("Initial availability fallback timer is not pending");
              callback();
            };
          }
          const originalFetch = window.fetch.bind(window);
          window.__seatwiseAvailabilityHarness = harness;
          window.__seatwiseAvailabilitySubscriptionFactory = (eventId, callbacks) => {
            harness.callbacks = callbacks;
            document.documentElement.dataset.availabilitySubscription = String(eventId);
            return { unsubscribe() {} };
          };
          harness.confirmSubscription = () => harness.callbacks.connected();
          harness.resolveNext = (snapshot) => {
            const pending = harness.pending.shift();
            if (!pending) throw new Error("No deferred availability request is pending");
            pending(new Response(JSON.stringify({ data: snapshot }), {
              status: 200,
              headers: { "Content-Type": "application/json" },
            }));
          };
          harness.snapshotWithReservedSeat = (seatNumber) => {
            const snapshot = structuredClone(harness.lastSnapshot);
            harness.reserveSeat(snapshot, seatNumber);
            return snapshot;
          };
          harness.reserveSeat = (snapshot, seatNumber) => {
            const row = snapshot.rows.find((item) => String(item.row_id) === "1");
            row.reserved_seats = [...new Set([...row.reserved_seats, seatNumber])].sort((a, b) => a - b);
            snapshot.reserved_count = snapshot.rows.reduce((sum, item) => sum + item.reserved_seats.length, 0);
            snapshot.available_count = snapshot.seat_count - snapshot.reserved_count;
          };
          window.fetch = async (input, init = {}) => {
            const url = new URL(typeof input === "string" ? input : input.url, window.location.href);
            if (url.pathname === "/api/v1/events/#{@event.id}" && (!init.method || init.method === "GET")) {
              harness.eventRequests += 1;
              document.documentElement.dataset.availabilityEventRequests = String(harness.eventRequests);
              if (harness.failNext) {
                harness.failNext = false;
                return new Response(JSON.stringify({ error: { code: "unavailable", message: "Temporary failure" } }), {
                  status: 503,
                  headers: { "Content-Type": "application/json" },
                });
              }
              if (harness.deferNext) {
                harness.deferNext = false;
                return new Promise((resolve) => harness.pending.push(resolve));
              }
              const response = await originalFetch(input, init);
              const body = await response.clone().json();
              harness.lastSnapshot = body.data;
              if (harness.nextReservedSeat !== null) {
                harness.reserveSeat(harness.lastSnapshot, harness.nextReservedSeat);
                harness.nextReservedSeat = null;
                body.data = harness.lastSnapshot;
                return new Response(JSON.stringify(body), {
                  status: response.status,
                  headers: response.headers,
                });
              }
              if (harness.changeBeforeFirstSnapshot) {
                harness.changeBeforeFirstSnapshot = false;
                const row = harness.lastSnapshot.rows.find((item) => String(item.row_id) === "1");
                harness.changedSeat = Array.from({ length: row.seat_count }, (_, index) => index + 1)
                  .find((seatNumber) => !row.reserved_seats.includes(seatNumber));
                if (!harness.changedSeat) throw new Error("No open seat available for the availability-change test");
                harness.reserveSeat(harness.lastSnapshot, harness.changedSeat);
                body.data = harness.lastSnapshot;
                return new Response(JSON.stringify(body), {
                  status: response.status,
                  headers: response.headers,
                });
              }
              return response;
            }
            return originalFetch(input, init);
          };
        })();
      JS
      result = page.driver.browser.execute_cdp(
        "Page.addScriptToEvaluateOnNewDocument",
        source: source
      )
      @availability_preload_identifier = result.fetch("identifier")
    end

    def confirm_availability_subscription
      page.execute_script("window.__seatwiseAvailabilityHarness.confirmSubscription()")
    end

    def availability_event_request_count
      page.evaluate_script("window.__seatwiseAvailabilityHarness.eventRequests")
    end

    def begin_checkout(wait_for_payment: true)
      find("button[data-seat='4'][data-row='1']").click
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
        window.__checkoutSessionCalls = 0;
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
            window.__checkoutSessionCalls += 1;
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
            window.__availabilityDeleteCalls = (window.__availabilityDeleteCalls || 0) + 1;
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
                unmount: () => {
                  delete document.querySelector("[data-express-checkout-element]").dataset.mountedElement;
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
                unmount: () => {
                  const target = document.querySelector("[data-payment-element]");
                  delete target.dataset.mountedElement;
                  target.replaceChildren();
                },
              }),
            });
          },
        });
      JS
    end
  end
end
