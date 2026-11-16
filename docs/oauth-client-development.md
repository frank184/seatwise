# OAuth client development

Seatwise is the OAuth authorization server and `/api/v1` resource server. The Portal browser app and external browser apps use the same Authorization Code + PKCE protocol. Browser clients are public clients: their client ID is public and they do not have a client secret.

## Development clients

After explicitly applying migrations to a fresh database, create the local records, then start or restart the app. This follows the repository's manual migration workflow; application startup does not prepare or migrate the database.

```sh
bin/rails db:migrate
bin/rails db:seed
```

The development-only seed helper is idempotent. Inspect the registered public identifiers and exact callbacks with:

```sh
bin/rails runner 'Doorkeeper::Application.order(:name).each { |app| puts "#{app.name}: client_id=#{app.uid} callback=#{app.redirect_uri} confidential=#{app.confidential?}" }'
```

The seeded Portal callback is `http://localhost:3000/oauth/callback`. The example external client callback is `https://oauth-client.example.test/callback`. Share client IDs and callback URLs as needed; do not create or distribute a browser client secret. This MVP provisions apps through development seeds and controlled application records, not public self-registration.

To permit an external browser origin during local development, set a comma-separated exact origin allowlist before starting Rails:

```sh
OAUTH_ALLOWED_ORIGINS="https://oauth-client.example.test,http://localhost:4000" bin/rails server
```

The same allowlist is used only for cross-origin `POST /oauth/token`, `POST /oauth/revoke`, and `/api/v1/*` requests. It does not enable credentialed cross-origin cookies. The `/oauth/authorize` interaction is a top-level browser redirect on the Seatwise origin and uses the Seatwise sign-in session. Production should set an explicit `OAUTH_ALLOWED_ORIGINS`; an empty value allows no external origins.

## Registering an external browser client

Create the OAuth application record through the controlled application provisioning path with:

- an exact HTTPS callback URI (including path and port);
- `confidential: false` and no client secret;
- the minimum scopes the client needs: `reservations:read` and, only if it creates or manages reservations, `reservations:manage`.

Loopback development callbacks may use HTTP, but the full URI must still match the registered callback exactly. Authorization requests require `response_type=code`, a cryptographically random `state`, a high-entropy PKCE verifier, its base64url SHA-256 challenge, and `code_challenge_method=S256`.

## Shared protocol endpoints

1. Redirect the user agent to `GET /oauth/authorize` with `client_id`, exact `redirect_uri`, `response_type=code`, requested `scope`, `state`, `code_challenge`, and `code_challenge_method=S256`.
2. Seatwise authenticates the customer with its email OTP flow when needed and returns the short-lived authorization code to the registered callback with the original `state`.
3. Exchange the code at `POST /oauth/token` using form encoding and the same `client_id` and `redirect_uri`, plus the original `code_verifier`. Public clients do not send a secret.
4. Send the opaque access token as `Authorization: Bearer <access_token>` to the scoped `/api/v1` endpoints. Access tokens expire after 15 minutes and there is no refresh token in this MVP; begin authorization again when needed. Customer ownership is enforced by the API in addition to OAuth scopes.

Example authorization URL parameters:

```text
client_id=<public-client-id>
redirect_uri=https%3A%2F%2Fclient.example%2Foauth%2Fcallback
response_type=code
scope=reservations%3Aread
state=<random-state>
code_challenge=<base64url-sha256-of-verifier>
code_challenge_method=S256
```

Example token exchange:

```sh
curl -X POST https://seatwise.example/oauth/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'grant_type=authorization_code' \
  --data-urlencode 'client_id=<public-client-id>' \
  --data-urlencode 'redirect_uri=https://client.example/oauth/callback' \
  --data-urlencode 'code=<authorization-code>' \
  --data-urlencode 'code_verifier=<original-verifier>'
```

Example private API request and token revocation:

```sh
curl https://seatwise.example/api/v1/reservations \
  -H 'Authorization: Bearer <access-token>' \
  -H 'Accept: application/json'

curl -X POST https://seatwise.example/oauth/revoke \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode 'client_id=<public-client-id>' \
  --data-urlencode 'token=<access-token>'
```

Do not put authorization codes, PKCE verifiers, or access tokens in application links, logs, analytics, or persistent browser storage. The authorization code appears only in the required short-lived OAuth callback URL; the Portal removes callback parameters from the address bar before exchanging it. The Portal keeps its access token and one in-flight PKCE transaction in tab-scoped `sessionStorage`, validates `state`, consumes the transaction before exchange, and stores the token only until its 15-minute expiry. This protects against persistence across browser restarts but remains exposed to same-origin script execution.
