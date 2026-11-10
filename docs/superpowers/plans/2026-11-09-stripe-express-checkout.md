# Stripe Express Checkout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the guest reservation flow with real five-minute holds and Stripe test-mode checkout using the Express Checkout Element and Payment Element, while introducing a replaceable development payment-provider configuration seam.

**Architecture:** Keep local Stripe test credentials in Rails development encrypted credentials, with Stripe-specific environment-variable overrides for other runtimes; never send a secret key to the browser. `RAILS_ENV` selects Rails behavior and credentials, while `STRIPE_*` values select Stripe configuration. A production-mode shared test deployment can therefore receive sandbox keys through its environment without loading development credentials. Add an in-memory development organization/provider response and a server-side provider resolver, so later work can replace these with organization-owned database records without changing checkout consumers. The portal will use the existing reservation API's automatic allocation, then create a Checkout Session in Elements mode and confirm only through a verified Stripe event while the hold remains active.

**Tech Stack:** Rails 8.1, Ruby Stripe SDK, PostgreSQL, Rails encrypted credentials, versioned JSON API, Stimulus, Rails importmap, Stripe.js Elements, daisyUI.

**Spec:** [V1 requirements](../../requirements.md), [API contract](../../api.md), and [entity draft](../../entities.md). Stripe integration references: [Express Checkout Element](https://docs.stripe.com/elements/express-checkout-element), [Payment Element](https://docs.stripe.com/payments/payment-element), [Checkout Sessions for Elements](https://docs.stripe.com/payments/accept-a-payment?platform=web&ui=elements), and [Checkout fulfillment](https://docs.stripe.com/checkout/fulfillment).

## Global Constraints

- A reservation hold lasts exactly five minutes; the server supplies its expiry and only an unexpired hold can become confirmed.
- Reservation quantity is 1–6 adjacent seats, automatically allocated in row allocation order and then lowest available seat number.
- Stripe test credentials stay server-side; the browser receives only the Stripe publishable key and a Checkout Session client secret.
- This implementation accepts test-mode Stripe keys only and does not enable live charges.
- Payment confirmation comes from a signature-verified Stripe event or server-side session reconciliation, never from a browser redirect alone.
- Do not add organization, staff, or payment-provider database records; seed data; Stripe Connect; a deployment workflow; Kamal configuration; or onsite card collection in this iteration.
- Do not collect or persist raw card numbers, expiration dates, or CVC values. Stripe Elements owns those fields.
- Local development uses the existing trusted-caller API posture; customer authentication remains outside this checkout slice.

## Starting Checkpoint

- Implementation starts on branch `stripe-express-checkout`, created from the current repository checkpoint.
- Local development credentials are already created in `config/credentials/development.yml.enc` with `stripe.secret_key` and `stripe.publishable_key`. The matching `config/credentials/development.key` is local-only and ignored by Git; the encrypted credentials file is included in the checkpoint commit.
- The default `config/credentials.yml.enc` and `config/master.key` remain intact. Rails uses the development credentials file in development; another Rails environment does not inherit or merge those values.
- A shared test deployment may run with `RAILS_ENV=production` and receive sandbox Stripe keys as `STRIPE_*` environment variables. `RAILS_MASTER_KEY` only unlocks the credentials selected by `RAILS_ENV`; it does not select a different credential environment. Keep deployment automation and Kamal configuration out of scope.
- Do not repeat credential generation or credential-file setup. Continue with resolver/configuration behavior and the customer checkout flow below.

## Review Focus

- Missing or malformed development Stripe credentials leave checkout visibly unavailable and never leak secret values; cover configuration validation and the provider endpoint's disabled response.
- A repeated checkout-session request for one held reservation reuses the same pending payment/session; cover the endpoint with repeated requests.
- Stripe reports no eligible wallets for the test account/browser; keep the Payment Element available and hide the empty Express Checkout region.
- Stripe returns to the portal before the webhook arrives; show a pending state and poll/reconcile server-side rather than claiming success from the return URL.
- A paid Checkout Session arrives after the five-minute hold expires; do not confirm or reallocate the expired reservation, and record a payment state that clearly requires follow-up.

---

### Task 1: Implement the development Stripe configuration and SDK boundary

**Files:**
- Modify: `Gemfile`, `Gemfile.lock`
- Modify: `compose.yaml`
- Create: `app/services/payment_providers/development_stripe.rb`
- Create: `test/services/payment_providers/development_stripe_test.rb`
- Create: `docs/payments.md`

**Interfaces:**
- Produces `PaymentProviders::DevelopmentStripe.configuration`, returning a typed configuration with `secret_key`, `publishable_key`, `webhook_secret`, `ticket_price_cents`, and `currency`.
- Read `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_DEVELOPMENT_TICKET_PRICE_CENTS`, and `STRIPE_DEVELOPMENT_CURRENCY` from `ENV` first, then fall back to `Rails.application.credentials.dig(:stripe, ...)`; require `sk_test_`/`pk_test_` keys and a positive integer ticket price. Default development price is 1000 cents per seat in `cad` until event pricing exists. Environment-variable precedence permits sandbox Stripe keys in a production-mode shared test deployment without changing `RAILS_ENV`.
- Accept credentials named `stripe.secret_key`, `stripe.publishable_key`, `stripe.webhook_secret`, `stripe.ticket_price_cents`, and `stripe.currency`; `RAILS_MASTER_KEY` unlocks environment credentials in a hosted development runtime.

- [ ] **Step 1: Write configuration tests** for environment-variable precedence, development-credential fallback, valid `sk_test_` configuration, and disabled/malformed configuration when credentials are missing or a live `sk_live_` key is supplied.
- [ ] **Step 2: Run the focused tests** with `docker compose exec -T -e RAILS_ENV=test rails bin/rails test test/services/payment_providers/development_stripe_test.rb -v`; expected: tests fail because the resolver is not implemented.
- [ ] **Step 3: Add the Stripe Ruby SDK and resolver**. Keep credential lookup and validation in `PaymentProviders::DevelopmentStripe`; do not set a global Stripe secret in code that can leak it to rendering or logs.
- [ ] **Step 4: Pass the five optional Stripe environment overrides through Compose.** Document that local development credentials are already provisioned, how the Rails environment selects credentials, how sandbox `STRIPE_*` overrides work in a production-mode shared test deployment, local Compose setup, and that secret values must not enter source control or chat. Keep deployment automation and Kamal files untouched.
- [ ] **Step 5: Rebuild the Rails development image and run the focused tests**; expected: all resolver cases pass and the test output contains no credential values.

### Task 2: Publish a replaceable development organization/provider response

**Files:**
- Create: `app/controllers/api/v1/organizations_controller.rb`
- Create: `app/views/api/v1/organizations/show.json.jbuilder`
- Modify: `config/routes.rb`
- Create: `test/controllers/api/v1/organizations_controller_test.rb`

**Interfaces:**
- Produces `GET /api/v1/organizations/development` with `{ "data": { "id": "development", "payment_provider": ... } }`.
- `payment_provider` includes `id: "development-stripe"`, `provider_key: "stripe"`, `enabled`, and `publishable_key`. It never includes `secret_key` or `webhook_secret`.
- This is an in-memory singleton response, not an Active Record model. The client consumes this shape so the later organization API can replace the source without changing checkout rendering.

- [ ] **Step 1: Write endpoint tests** for the enabled response, missing credentials (`enabled: false` and a null publishable key), and the absence of every secret field.
- [ ] **Step 2: Run the focused endpoint tests**; expected: route/controller tests fail before implementation.
- [ ] **Step 3: Implement the namespaced endpoint** using `PaymentProviders::DevelopmentStripe.configuration`; return the provider's public configuration only and use a stable development organization ID.
- [ ] **Step 4: Run the endpoint tests**; expected: response contract and secret-redaction assertions pass.

### Task 3: Replace simulated reservation creation with the V1 hold API

**Files:**
- Modify: `app/javascript/controllers/portal/reservation_controller.js`
- Modify: `app/views/portal/reservations/_checkout_flow.html.haml`
- Create: `test/controllers/api/v1/reservations_controller_test.rb`

**Interfaces:**
- The portal submits `POST /api/v1/reservations` with `{ event_id, quantity, email }` and a stable `Idempotency-Key` for retries.
- The portal derives `quantity` from the current seat-count selection. Copy says the exact contiguous block is assigned when the hold is placed; V1 does not accept requested seat coordinates.
- `flow.reservation` is populated from the server response: `id`, `event_id`, `row_id`, inclusive `seat_start`/`seat_end`, `status`, and `expires_at`. The assigned server seats remain highlighted through payment and confirmation.

- [ ] **Step 1: Add tests** for successful hold creation using server-assigned seats, retry with the same idempotency key, unavailable seats, and invalid quantity; assert that a client-supplied seat coordinate cannot override automatic allocation.
- [ ] **Step 2: Run the controller tests** with `docker compose exec -T -e RAILS_ENV=test rails bin/rails test test/controllers/api/v1/reservations_controller_test.rb -v`; expected: the already implemented API contract passes.
- [ ] **Step 3: Wire `placeHold` to the endpoint**; preserve the user's email and selected quantity, disable duplicate submission while pending, use server expiry for the timer, and render the returned block in the seat map.
- [ ] **Step 4: Handle API failures in the form** without creating a local hold; retain input, refresh event availability after allocation conflict, and allow retry with a new idempotency key only after a definitive failed request.
- [ ] **Step 5: Run the controller tests again**; expected: valid requests persist one hold and return the assigned seats and expiry used by the browser.

### Task 4: Create and persist Stripe Checkout Session attempts

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_stripe_checkout_support.rb` (generate the timestamp when implementing)
- Modify: `app/models/payment.rb`
- Create: `app/models/stripe_webhook_event.rb`
- Create: `app/services/checkouts/create_stripe_session.rb`
- Create: `app/controllers/api/v1/reservation_checkouts_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/services/checkouts/create_stripe_session_test.rb`
- Create: `test/controllers/api/v1/reservation_checkouts_controller_test.rb`
- Modify: `test/models/payment_test.rb`

**Interfaces:**
- `POST /api/v1/reservations/:reservation_id/checkout/session` returns `payment_id`, `client_secret`, `amount`, `currency`, and `status`; it accepts no client-supplied amount, provider key, or Stripe credential.
- `Checkouts::CreateStripeSession.call(reservation:)` returns or reuses a pending `Payment` and its Checkout Session `client_secret`.
- Create a Checkout Session with `ui_mode: "elements"`, `mode: "payment"`, one ticket line item per held seat, the development price/currency, customer email, reservation/payment metadata, and a return URL containing the Stripe session placeholder.
- Persist Stripe Checkout Session ID in `payments.external_id`, `provider_key: "stripe"`, `amount` in minor units, and lowercase ISO currency. Add a unique index for external payment IDs, a partial unique index allowing one pending attempt per reservation, and a unique Stripe event ID in `stripe_webhook_events`.
- Backfill existing demo payments with `provider_key: "simulator"` and `currency: "cad"`; require both values for new attempts.
- Only create a session for a held, unexpired reservation. Keep provider/account database relationships deferred.

- [ ] **Step 1: Write service/controller tests** for amount computed server-side from seat count, valid session parameters, secret-free JSON, pending-session reuse, and `409` for an expired/cancelled reservation.
- [ ] **Step 2: Run focused tests**; expected: service and routes fail before implementation.
- [ ] **Step 3: Add the Stripe SDK call and payment persistence** in `Checkouts::CreateStripeSession`; inject/stub the Stripe client in tests and pass the secret key only at the server boundary.
- [ ] **Step 4: Add checkout-session and webhook-event schema constraints**; ensure concurrent retries cannot create multiple pending attempts for the same reservation and provider session IDs cannot be attached twice.
- [ ] **Step 5: Implement the endpoint and run its tests**; expected: valid requests return only the client secret and total, while missing provider configuration returns a client-safe unavailable response.

### Task 5: Build the portal checkout using Stripe Elements

**Files:**
- Modify: `app/views/portal/reservations/_checkout_flow.html.haml`
- Modify: `app/javascript/controllers/portal/reservation_controller.js`
- Modify: `app/views/layouts/portal.html.haml` to load Stripe.js on portal pages
- Create: `test/application_system_test_case.rb`
- Create: `test/system/portal/reservation_checkout_test.rb`

**Interfaces:**
- The portal fetches `GET /api/v1/organizations/development`, then requests a Checkout Session after a valid hold.
- Stripe.js initializes Elements with the public key and returned client secret. Render `expressCheckout` above `payment` in the same payment card; use one normal Seatwise submit action for Payment Element and the Element's `confirm` event for wallet buttons.
- Keep similarly sized columns with the order summary, hold timer, and cancel action on the left and payment on the right; stack them on narrow screens. Use distinct subtle card tints, and do not force page scroll/focus to the stage heading on transitions.
- Show a client-facing error and disable payment when provider configuration or session creation is unavailable.

- [ ] **Step 1: Add system tests** for the provider loading state, no-wallet state, card-only path, wallet confirm path, disabled provider response, and preserved held-seat display. Stub Stripe.js in these tests; reserve a real Stripe test-mode run for Task 7.
- [ ] **Step 2: Replace fake card/provider buttons and card fields** with Express Checkout Element and Payment Element containers. Load Stripe.js from Stripe's hosted script, render Elements-provided branded buttons, and keep the two Elements within one payment column.
- [ ] **Step 3: Implement payment submission** with `elements.submit()` and `stripe.confirmPayment`; handle validation, decline, authentication, processing, and redirect return states without storing card data.
- [ ] **Step 4: Run browser tests**; expected: payment methods are Stripe-rendered, the manual PayPal button is gone, and the card fallback remains usable when no wallet is eligible.

### Task 6: Confirm reservations from verified Stripe events and return reconciliation

**Files:**
- Create: `app/controllers/api/v1/stripe_webhooks_controller.rb`
- Create: `app/services/checkouts/process_stripe_event.rb`
- Create: `app/services/reservations/expire_if_due.rb`
- Modify: `app/controllers/api/v1/reservation_checkouts_controller.rb`
- Modify: `app/models/stripe_webhook_event.rb`
- Modify: `config/routes.rb`
- Create: `test/controllers/api/v1/stripe_webhooks_controller_test.rb`
- Create: `test/services/checkouts/process_stripe_event_test.rb`
- Create: `test/services/reservations/expire_if_due_test.rb`

**Interfaces:**
- `POST /api/v1/payment_webhooks/stripe` verifies the `Stripe-Signature` header with the configured webhook secret, accepts supported Checkout Session completion/async-success/async-failure events, and returns `400` for invalid signatures.
- `Checkouts::ProcessStripeEvent.call(event:)` idempotently matches the Stripe session to the local `Payment` and reservation; only a paid session for a still-held, unexpired reservation confirms it.
- `GET /api/v1/reservations/:reservation_id/checkout?session_id=cs_...` validates that the Checkout Session belongs to this reservation, reconciles it server-side, and returns `processing`, `succeeded`, `failed`, or `expired`; a return URL parameter by itself never confirms payment.
- `Reservations::ExpireIfDue.call(reservation:)` takes the reservation lock and transitions an overdue `held` reservation to `expired`, releasing inventory before checkout status or payment confirmation is returned.
- A success received after hold expiry leaves the reservation expired and records `late_success` for explicit follow-up; it never reclaims seats or silently reports a confirmed booking.

- [ ] **Step 1: Write expiry and webhook tests** for the due/active hold boundary, valid and invalid signatures, duplicate event delivery, event/payment/reservation mismatch, succeeded and failed sessions, and success after hold expiry.
- [ ] **Step 2: Run focused webhook tests**; expected: they fail before the signature-verified processing path exists.
- [ ] **Step 3: Implement signature verification and transactional processing**; persist each Stripe event ID once and reuse the same transition service for webhook and return reconciliation.
- [ ] **Step 4: Add status polling to the portal**; keep a “Confirming payment” state until the server reports success, then advance progress to Confirmation and show the real reservation/payment summary.
- [ ] **Step 5: Run focused API and browser tests**; expected: only server-confirmed payment advances the flow, and duplicate webhook events have no additional effect.

### Task 7: Document setup and verify the Stripe test-mode happy path

**Files:**
- Modify: `docs/payments.md`
- Modify: `docs/api.md`
- Modify: `docs/requirements.md` only where implementation status needs updating

- [ ] **Step 1: Document** the already-provisioned local development credential names, Rails credential selection, Stripe environment-variable overrides, checkout/provider/webhook response contracts, Stripe CLI webhook forwarding, and reset/retry instructions. State clearly that pricing is a temporary `$10 CAD` per-seat development value.
- [ ] **Step 2: Run the Rails test suite and formatting checks** for changed Ruby, HAML, and JavaScript files using the repository's Docker Compose commands.
- [ ] **Step 3: Exercise the happy path with Stripe test mode**: create a five-minute hold, pay with a Stripe test method, return to Seatwise, receive/reconcile the webhook, see confirmation progress advance, and verify the held seats remain highlighted.
- [ ] **Step 4: Exercise failure paths**: no test credentials, declined card, no eligible wallet, webhook signature failure, duplicate event delivery, and hold expiry during checkout; verify no false confirmation occurs.
