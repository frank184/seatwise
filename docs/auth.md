# Seatwise auth

> **Implementation status:** The routes and flows below are planned. Customer sign-in, browser sessions and API credentials are not implemented yet.

Seatwise uses passwordless email sign-in to establish customer identity. That identity determines which reservations a customer can manage through the browser or API.

## Guest checkout

A guest provides their email when placing a five-minute hold, then completes payment. Seatwise finds or creates the customer by email and associates the hold with that customer. Checkout can finish before email verification. Hold creation returns a link and a checkout bearer token scoped to that reservation.

Successful payment confirms an unexpired hold. Seatwise then emails a booking reference and a link to manage the reservation. The management page requests a sign-in code if the customer has no active session. A confirmed booking can also supply a [saved ticket](tickets.md).

## Sign-in flow

1. Seatwise finds or creates the `Customer` when someone submits an email address, then sends a short-lived, single-use code. A new customer starts with `email_verified_at` unset.
2. On successful verification, Seatwise consumes the code, sets `email_verified_at` if it is unset, and starts a browser session.
3. The session lets the customer open their booking pages and obtain an API access token to manage reservations. Seatwise sends confirmations and event updates to the address provided at checkout.

A browser session expires 30 days after sign-in or ends earlier at sign-out. Seatwise enforces the deadline on the server. Browsing does not extend it. An expired session or a fresh browser can request a new code. The email code has its own expiry.

## Browser auth endpoints

These same-origin routes live outside `/api/v1`. Browser auth writes require CSRF validation.

| Method and path | Request | Success |
| --- | --- | --- |
| `POST /auth/code` | `{"email":"buyer@example.com"}` | `202 Accepted` with the same response for new and returning customers. Seatwise sends a code to the address. |
| `POST /auth/verify` | `{"email":"buyer@example.com","code":"123456"}` | `204 No Content` and a new browser session cookie. |
| `POST /auth/token` | Active browser session. Empty body. | `200` with `access_token`, `token_type` set to `Bearer`, and `expires_at` in UTC ISO 8601. |
| `DELETE /auth/session` | Browser session. | `204 No Content` and the session cookie cleared. Seatwise revokes tokens issued through the session. |

Verification returns `422` for an invalid, expired or consumed code. Rate-limited code requests or verification attempts return `429`. Token exchange returns `401` if the browser has no active session. Responses carrying a token use `Cache-Control: no-store`.

## Identity and session model

| Entity | Responsibility |
| --- | --- |
| `Customer` | A stable ID, a unique `email`, and an `email_verified_at` timestamp set on first verification. The record also stores the pending code digest, expiry, and failed attempt count. |
| `Session` | Associates an authenticated browser with a customer for up to 30 days from sign-in. |
| API access token | Identifies a customer to the API. The token record has an expiry and can be revoked. Tokens issued to the portal are associated with the browser session that issued them. |
| `Reservation` | References its owner through `customer_id`. Its hold expiry and booking status have their own lifecycle. |

Each customer has at most one active sign-in code. Issuing a new code replaces the previous one. Limit failed attempts and consume a valid code atomically so concurrent requests can use it only once. A returning customer still needs a fresh code to establish a new session.

## Access by caller

| Caller | Credential and permissions |
| --- | --- |
| Guest | Browse published events and place a hold with a checkout email. Use the checkout credential to start payment and view its status for that hold. Reservation management requires a customer credential. |
| Seatwise browser | Use the session cookie for HTML pages and a CSRF-protected token exchange. Send the resulting access token as `Authorization: Bearer <token>` to customer API endpoints. |
| External customer client | Authenticate the customer and use the same `Authorization: Bearer <token>` interface and access token format as the portal. |
| Payment provider or simulator | Use a service credential validated by the payment notification handler. That credential authorizes notifications only. |
| Venue scanner | Verify the signed [ticket](tickets.md) using the preloaded public key and event configuration. Offline verification uses the ticket directly. |

For protected customer requests, the API resolves the bearer token to a `Customer` and checks that ID against `Reservation.customer_id` for lookup, cancellation and saved-ticket delivery. The API ignores browser session cookies for authentication.

## Checkout credential

Hold creation issues a checkout bearer token scoped to one reservation. It authorizes checkout status and payment start for that reservation only. The browser reads the credential from the checkout link's URL fragment and sends it in the `Authorization` header on checkout API requests. Other API clients can use the token returned in the creation response directly.

The checkout credential expires 15 minutes after the hold is created. Payment can start only during the five-minute hold. The remaining time lets a guest read the outcome after the hold deadline. Replaying a successful hold request returns the same credential and deadlines. The checkout token grants no customer session, reservation management access or ticket download.

[URI fragment handling (RFC 3986)](https://www.rfc-editor.org/rfc/rfc3986.html#section-3.5)

## API access tokens

Use one format for customer API access tokens. The initial format is a short-lived, revocable opaque token. The server looks up the token's verifier, customer ID and expiry before authorizing the request.

The portal exchanges its active session for a token using a same-origin, CSRF-protected POST outside `/api/v1`. The portal keeps the token in memory and reuses it until expiry. It can request another token while the session is active. A portal token expires no later than its issuing session. Signing out ends the session and revokes the tokens issued through it.

The [admission ticket](tickets.md) carries its own signature for offline verification. It serves a separate purpose from an API access token.

[Bearer token usage (RFC 6750)](https://www.rfc-editor.org/rfc/rfc6750.html)
