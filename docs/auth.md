# Authentication and authorization

> **Status:** This document describes the customer authentication and authorization behavior currently implemented in Seatwise. Staff, organization membership, and workforce identity integration are future work.

## Layers and boundaries

Seatwise uses one Rails application for three distinct interfaces:

| Layer | Routes | Purpose |
| --- | --- | --- |
| Portal HTML | `/`, `/events/*`, `/sign-in*`, `/account/reservations` | Event discovery, reservation experience, OTP forms, and the Portal's OAuth client pages. Controllers and views are under `Portal::` and `app/views/portal/`. |
| OAuth authorization server | `/oauth/authorize`, `/oauth/token`, `/oauth/revoke` | Doorkeeper Authorization Code + PKCE. OTP establishes the Rails customer session; OAuth issues client-bound API tokens. |
| Versioned resource API | `/api/v1/*` | Public event reads, guest-cart operations, and customer-token reservation access. The API does not use the Portal's Rails login session as a bearer token. |

Payment webhooks are a separate provider-authenticated route: `POST /api/v1/payment_webhooks/stripe` verifies Stripe's signature. Development email previews are mounted at `/letter_opener` only in development.

The current resource owner is a verified `Customer`. There is no separate Principal/Identity model, staff actor, organization membership, OIDC identity token, or workforce tenant integration. A later staff actor can be added without changing the bearer-token transport, while having separate Customer and Staff records is acceptable.

## Customer identity and guest-cart lifecycle

Email supplied at checkout is contact information, not authentication. Reservation creation can create an unverified `Customer` record for that address. A customer may also start sign-in before booking; requesting a code creates the record if needed. The customer becomes a verified identity only after entering the valid OTP.

1. Public visitors read `GET /api/v1/events` and `GET /api/v1/events/:id` without a token.
2. Before creating a guest hold, the Portal bootstraps a cart with `POST /api/v1/guest_sessions` using `transport=cookie`. The API stores a digest of a random secret and sets an HttpOnly `guest_cart` cookie. Direct API clients may use `transport=body`; that returns the secret once for `Authorization: Guest <secret>` use and is not the Portal's cookie flow.
3. The cart credential is valid for 30 days, and the browser cookie uses `SameSite=Lax`, `HttpOnly`, and `Secure` in production. A reservation hold lasts 5 minutes. Each hold is associated with the cart, and the cart secret alone can access only those cart reservations. An explicit `bin/rails guest_carts:cleanup` task can delete expired cart rows, but it is not currently scheduled.
4. Guest reservation creation, cancellation, and checkout operations require the cart credential. A reservation ID by itself is not authorization. Guest cart access does not list every reservation for an email or permit ticket/account management.
5. Successful OTP verification resets the Rails session, establishes the verified customer session, and rotates the cart secret while preserving the cart and its active holds. The old cart secret stops working. Payment alone does not establish customer identity.

The Rails session is a CookieStore cookie named `_seatwise_session`, configured `HttpOnly`, `SameSite=Lax`, secure in production, with a 30-day expiry. OTP verification sets `session[:customer_id]` only after the database-backed challenge succeeds. Sign-out resets that session and rotates any current guest-cart secret.

## Email OTP sign-in

Portal pages and form actions:

| Method and path | Behavior |
| --- | --- |
| `GET /sign-in` | Render the sign-in form. |
| `POST /sign-in/code` | Normalize the email, create/find the Customer, persist a digest and expiry, and send a one-time code. Existing and unknown addresses receive the same generic response. |
| `GET /sign-in/verify` | Render the code-entry page for the pending customer stored in the Rails session. |
| `POST /sign-in/verify` | Check the code against the pending session customer; on success verify the email and establish the Rails login session. |
| `POST /sign-out` | Reset the login session and rotate an existing guest-cart credential. |

Codes are six digits, expire after 10 minutes, can be used once, have a 60-second resend cooldown, and allow at most five verification attempts. Code requests are limited to 5 per normalized email and 20 per remote IP in 15 minutes. The database stores a digest, not the code. Email, code, token, and related sensitive parameter names are filtered from Rails logs. OTP itself does not issue an API access token. The OTP email is sent synchronously; if production SMTP delivery fails, the request fails and the customer may request another code after the resend cooldown.

After OTP, a ticket email's `/sign-in?return_to=/account/reservations` link redirects to the reservation page. That page starts the Portal's ordinary OAuth flow, so reservation reads still require an OAuth access token. OAuth authorization resumes through `/oauth/authorize` after OTP when the customer begins there.

## OAuth clients and PKCE

Doorkeeper is Seatwise's OAuth authorization server. Only the Authorization Code grant is enabled. PKCE is mandatory and only `S256` is accepted. The app additionally requires an exact registered redirect URI (including local callback ports), and production callback URIs must use HTTPS. Authorization codes expire after 10 minutes. Access tokens expire after 15 minutes; refresh tokens are not issued. Token secrets are hashed in the database. The token returned to a client is an opaque bearer value, not a JWT or an OIDC ID token.

The default scope is `reservations:read`; `reservations:manage` is optional. Doorkeeper limits requested scopes to those registered on the client. The Portal client skips the separate consent screen; other clients use the normal Doorkeeper authorization flow. Token revocation is available at `POST /oauth/revoke`. Doorkeeper's application-management and token-inspection controllers are not mounted.

The development OAuth clients are seeded only in development and idempotently by name. On a fresh development database, migrations and seeds are explicit operations; booting Rails does not migrate or seed automatically:

```sh
bin/rails db:migrate
bin/rails db:seed
```

Retrieve public IDs and callbacks locally with:

```sh
bin/rails runner 'Doorkeeper::Application.order(:name).each { |app| puts "#{app.name}: client_id=#{app.uid} callback=#{app.redirect_uri} confidential=#{app.confidential?}" }'
```

The seeded clients are `Seatwise Portal` (`http://localhost:3000/oauth/callback`) and `Seatwise Development OAuth Client` (`https://oauth-client.example.test/callback`). Both are public clients with no secret and the two customer scopes. The client ID and callback URI can be shared; never add a browser client secret. See [OAuth client development](oauth-client-development.md) for the external-client setup and request examples.

**Production OAuth provisioning is not yet bootstrapped.** The development-only seed creates the `Seatwise Portal` client, Portal pages look it up by name, and Doorkeeper application-management routes are disabled. A production deployment must provision that public client through a controlled operator path before `/oauth/start` or `/account/reservations` can work; no supported provisioning command or UI is implemented yet. Do not assume the development seed command provisions production OAuth clients.

### Portal client flow

The Portal browser client does not trade its Rails cookie for a special API token. Its Stimulus controller creates a random `state` and PKCE verifier, stores the transaction in tab-scoped `sessionStorage`, and redirects to `/oauth/authorize`. Doorkeeper resolves the verified Customer from the Rails session; if absent, its authenticator redirects to `/sign-in` and preserves the validated OAuth request. After authorization, the Portal callback validates `state`, removes callback parameters from the address bar, exchanges the code at `/oauth/token`, and stores the access token in `sessionStorage` until expiry. It then calls `/api/v1` with `Authorization: Bearer ...`.

When the token expires or the reservation page is reopened without a valid tab token, the Portal starts authorization again. Sign-out clears the token and PKCE transaction, requests token revocation, then signs out of the Rails session. A temporary revocation failure does not prevent the Rails sign-out. Tab-scoped storage limits persistence across browser restarts but remains available to same-origin JavaScript.

Third-party browser clients use the same authorization, token, revocation, and API endpoints. They register a public Doorkeeper application with exact callbacks, implement their own state and PKCE verifier handling, and call the resource API with the resulting bearer token. No Portal-only token exchange endpoint exists.

## Public, guest, and customer API access

`GET /api/v1/events` and `GET /api/v1/events/:id` are public; the current event API has no draft/published visibility filter. Guest mutations use either the Portal cookie or a direct client's `Authorization: Guest <secret>` credential. Customer access requires a Doorkeeper bearer token whose resolved resource owner is a verified Customer.

| API operation | Required access |
| --- | --- |
| `GET /api/v1/reservations` and `GET /api/v1/reservations/:id` | Customer bearer token with `reservations:read`; results are scoped to `current_customer.reservations`. |
| `POST /api/v1/reservations` | Guest-cart credential, or customer bearer token with `reservations:manage`. For customer requests, the API derives the Customer from the token and rejects mismatched submitted email/customer ID. |
| `DELETE /api/v1/reservations/:id` | Guest-cart credential, or customer bearer token with `reservations:manage`; only owned active holds may be cancelled. |
| `POST /api/v1/reservations/:reservation_id/checkout/session` | Guest-cart credential, or customer bearer token with `reservations:manage`. |
| `GET /api/v1/reservations/:reservation_id/checkout` | Guest-cart credential, or customer bearer token with `reservations:read`. |
| `POST /api/v1/reservations/:reservation_id/checkout/reconcile` | Guest-cart credential, or customer bearer token with `reservations:manage`. |

Authorization is enforced at both the OAuth scope and record layers. Customer collection queries start from `current_customer.reservations`; individual actions check ownership through `ReservationPolicy`. Unauthorized customer access requires a valid customer bearer token (401); a valid token missing a required scope is forbidden (403); an unowned reservation is reported as not found. An admission ticket is not a reservation-management credential.

The Portal's cookie-authenticated API mutations require the exact configured Portal `Origin` and reject `Sec-Fetch-Site: cross-site`. These API requests are not Rails controller session-authenticated and do not use the Portal login cookie as their credential. Rails Portal forms use CSRF protection. `Rack::Cors` allows only explicitly configured origins for cross-origin `/oauth/token`, `/oauth/revoke`, and `/api/v1/*` requests; it does not allow credentialed cross-origin cookies. Set `OAUTH_ALLOWED_ORIGINS` to comma-separated exact origins for external clients. Production should provide an explicit allowlist; empty means no cross-origin access.

## Ticket email and development preview

When a verified Stripe event confirms payment, Seatwise inserts one `TicketDelivery` row for the reservation inside the confirmation transaction. A unique reservation index prevents duplicate outbox rows when a provider event is replayed. After commit, a job sends `TicketMailer.confirmation`; failed jobs retry up to ten attempts. A production recurring job checks pending rows every five minutes in case the first enqueue was lost. Delivery is at-least-once if the process fails after an external mail server accepts the message but before the row is marked delivered; the durable outbox row remains the retry source.

The ticket email contains the event name/time and seat row/range, then links to the Portal sign-in page with the reservation-management destination. It contains neither a reservation ID as proof nor an API token. The customer completes OTP, then the Portal uses PKCE and customer-scoped API access to display reservations.

Development sends mail to Letter Opener Web at `/letter_opener`. The OTP code is visible in the generated preview email while only its digest is stored in the database. The same preview shows the actual ticket confirmation email and its sign-in link. Letter Opener's route is mounted only in development and is unavailable in test and production.

Production requires SMTP credentials under encrypted Rails credentials at `smtp` (`address`, optional `port` defaulting to 587, `user_name`, `password`, and optional `authentication` defaulting to `plain`; STARTTLS is enabled). Delivery errors raise so the ticket background job can retry. `PORTAL_ORIGIN` configures the production Portal origin and mail links.

## Current limitations and future work

- Customers are the only OAuth resource-owner type. There are no staff accounts, organizations, staff membership/roles, admin identity, or Entra ID integration.
- There are no refresh tokens, OIDC login, JWT access tokens, OAuth application self-registration, or general account recovery/email-change flow.
- Guest carts are narrow reservation capabilities, not customer identities. Their 30-day expiry disables credential use, but expired database rows remain until an operator runs the cleanup task; recurring cleanup is not configured. Direct API body-transport guest secrets are shown once and have no browser cookie protections; clients must protect them as bearer credentials.
- The Portal keeps the access token in tab `sessionStorage`; a same-origin script compromise can read it until it expires or is revoked.
- Ticket delivery retries can send a duplicate only across the external-send/database-mark crash window; the outbox guarantees no lost record and a unique delivery row per reservation.
- The sign-in session lasts 30 days, access tokens 15 minutes, authorization codes 10 minutes, OTPs 10 minutes, and guest carts 30 days. These lifetimes are separate controls.

## References

- [V1 API](api.md)
- [Entities and customer ownership](entities.md#customer-identity-and-reservation-ownership)
- [OAuth client development](oauth-client-development.md)
- [OAuth 2.0 Authorization Framework](https://www.rfc-editor.org/rfc/rfc6749.html)
- [Proof Key for Code Exchange (PKCE)](https://www.rfc-editor.org/rfc/rfc7636.html)
- [Bearer Token Usage](https://www.rfc-editor.org/rfc/rfc6750.html)
