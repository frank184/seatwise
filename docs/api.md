# Seatwise API specification

> **Implementation status:** V1 health, public event reads, guest-session creation, guest-scoped reservation operations, customer OAuth sign-in and reservation access, development organization/provider, Stripe Checkout Session/reconciliation, Stripe webhooks, and post-payment ticket delivery are implemented. See [authentication and authorization](auth.md) for the complete customer flow and security boundaries.

The Seatwise JSON API exposes event availability, reservation holds, checkout, cancellation and payment confirmation. See the [V1 requirements](requirements.md).

## Conventions

- Routes are prefixed with `/api/v1`. JSON requests with a body use `Content-Type: application/json`.
- Treat identifiers as opaque values. Row IDs are scoped to an event. The order of rows in the availability response is the order used for allocation.
- Seat positions start at 1. `seat_start` and `seat_end` are inclusive.
- Timestamps are UTC ISO 8601 strings. The server determines hold expiry.
- Error responses use `{"error":{"code":"machine_readable_code","message":"Human-readable explanation"}}`.
- `/api/v1/*` is a JSON-only, client-neutral contract. It never reads or sets browser cookies and never relies on a Portal Rails session or Portal `Origin`. Clients send guest or customer credentials explicitly in `Authorization`; Portal JavaScript omits cookies on every V1 request. See [authentication and authorization](auth.md).
- Event reads are public. Guest-scoped reservation and checkout operations require the guest capability that owns the reservation. Customer operations require a customer bearer token with the required scope.

## Endpoints

| Method and path | Request | Success |
| --- | --- | --- |
| `GET /api/v1/up` | — | `200` with `{"status":"ok","api_version":"v1"}`. |
| `GET /api/v1/events` | — | `200` with a paginated `data` array of matching event summaries and a `meta` object. There is currently no draft/published visibility filter. |
| `GET /api/v1/events/:event_id` | — | `200` with an event summary including `id`, `name`, `ticket_price_cents`, and `starts_at`. |
| `GET /api/v1/organizations/development` | — | `200` with public, in-memory Stripe provider configuration. |
| `POST /api/v1/guest_sessions` | Empty JSON object. Limited to 20 requests per remote IP per minute. | `201` creates a `Guest` and returns its one-time `guest_token` plus `expires_at`. It never sets a cookie. |
| `GET /api/v1/reservations` | Requires a customer bearer token with `reservations:read`. Accepts `page`, `status=active|history|held|confirmed|cancelled|expired`, `venue_id`, and `q` (reservation number, event name, or venue name). | `200` with the customer's matching reservations in `data` and pagination plus customer-scoped venue options in `meta`; each reservation includes event name, date/time, and venue details. Pages contain up to 10 reservations. Due holds are marked expired before the list is returned. |
| `GET /api/v1/reservations/:id` | Requires a customer bearer token with `reservations:read`. | `200` with that customer's reservation; another customer's reservation is `404`. |
| `POST /api/v1/reservations` | `{"event_id":42,"quantity":2,"email":"buyer@example.com"}` and `Idempotency-Key`. Requires `Authorization: Guest <guest_token>` or a customer bearer token with `reservations:manage`. A customer-authorized Portal request may also send `X-Seatwise-Guest-Token` to link its guest capability to the hold for checkout recovery. | `201` with the held reservation and server-assigned seats. Customer identity comes from the bearer token, not request fields. |
| `DELETE /api/v1/reservations/:id` | Requires the owning guest token or a customer bearer token with `reservations:manage`. | `200` with the reservation marked cancelled if it was held. |
| `POST /api/v1/reservations/:reservation_id/checkout/session` | Empty JSON object; requires the owning guest token or a customer bearer token with `reservations:manage`. | `200` with the pending payment, Stripe Checkout Session ID, client secret, amount, and currency. |
| `GET /api/v1/reservations/:reservation_id/checkout?session_id=cs_...` | Requires the owning guest token or a customer bearer token with `reservations:read`. Reads locally persisted status only. | `200` with `processing`, `succeeded`, `failed`, or `expired`; does not contact Stripe or change payment/reservation state. |
| `POST /api/v1/reservations/:reservation_id/checkout/reconcile` | `{"session_id":"cs_..."}`; requires the owning guest token or a customer bearer token with `reservations:manage`. | `200` with the reconciled checkout status after retrieving the session from Stripe. |
| `POST /api/v1/payment_webhooks/stripe` | Stripe raw event body and `Stripe-Signature` header. | `200` after supported signed event processing; invalid signatures return `400`. |

### Guest session flow

Guest-session creation is the deliberate unauthenticated bootstrap operation: no OAuth actor token is required, and the endpoint currently identifies clients only by request IP for rate limiting. This is not authentication of a registered OAuth client. The returned guest token is a narrowly scoped bearer capability for that Guest's reservation set.

```http
POST /api/v1/guest_sessions
Accept: application/json
Content-Type: application/json
```

```json
{}
```

```json
{
  "guest_token": "random-one-time-capability",
  "expires_at": "2026-12-17T18:00:00Z"
}
```

The client must retain the token privately and send it on guest-owned operations:

```http
Authorization: Guest random-one-time-capability
```

The token is not the Guest database ID. The database stores only its digest. A client that loses the token cannot use the guest credential to recover those reservations; completing customer OTP for the reservation email provides the separate customer-authenticated recovery route. Never place the guest token in a URL or logs.

For Portal requests made with a customer bearer token, `X-Seatwise-Guest-Token` is an optional secondary capability, not authentication for that request. When present and valid on reservation creation, the reservation remains owned by the bearer-token Customer and is also linked to that Guest. The Guest can then continue that specific reservation if the Portal's customer token expires, is revoked, or is cleared on sign-out; it does not grant access to the customer's reservation collection.

### Availability response

```json
{
  "data": {
    "id": 42,
    "name": "Saturday Matinee",
    "ticket_price_cents": 2500,
    "starts_at": "2026-11-14T14:00:00Z",
    "ends_at": "2026-11-14T16:00:00Z",
    "past": false,
    "venue": { "name": "Studio Theatre" },
    "rows": [
      {
        "row_id": 1,
        "label": "A",
        "allocation_order": 1,
        "seat_count": 10,
        "reserved_seats": [1, 2, 3, 4, 7, 8]
      }
    ],
    "seat_count": 10,
    "reserved_count": 6,
    "available_count": 4
  },
  "meta": { "api_version": "v1" }
}
```

Event show responses wrap the event in `data` and include `meta.api_version`. Event list responses use the same envelope, with an array in `data` and pagination values in `meta`. Row IDs and event IDs are numeric. Each row's `reserved_seats` contains seat numbers occupied by confirmed reservations and unexpired holds. Availability can change between this read and the hold request. For the example, a request for two seats would be allocated seats 5–6 if the inventory stays the same.

### Create reservation response

`201 Created` includes `Cache-Control: no-store`. The event layout is allocated automatically: choose 1–6 adjacent seats in the frontmost row with a suitable block, then the lowest available starting seat. The entire group is held for five minutes or the request fails without a partial reservation.

```json
{
  "id": 42,
  "event_id": 42,
  "row_id": 1,
  "seat_start": 5,
  "seat_end": 6,
  "status": "held",
  "expires_at": "2026-11-06T19:05:00Z"
}
```

Guest reservation creation requires `Authorization: Guest <guest_token>` plus a guest email; customer-token creation instead uses the verified customer associated with that token. A customer-authorized Portal reservation may include the secondary `X-Seatwise-Guest-Token` capability so it can retain guest-scoped checkout recovery. `POST /api/v1/guest_sessions` creates a Guest and returns its random capability once as JSON. Only a SHA-256 digest is stored. The guest token is a bearer capability: clients must keep it private and resend it explicitly; its possession grants access only to reservations linked to that Guest. API requests do not use cookie credentials or Portal-origin checks. A guest email is reservation contact data, not proof of customer identity.

One Guest can be linked to multiple reservations. Repeating the same event, quantity, email and guest with the same `Idempotency-Key` returns the original reservation with `200`, including when the Portal retries it through the linked guest capability after a customer-token failure. Changing those values or using the key from another guest returns `409`. A different or missing guest credential cannot continue the hold. Stale held reservations are marked expired during allocation and customer reservation listing, and the database overlap constraint remains the final guard against concurrent claims.

`status` is one of `held`, `confirmed`, `expired` or `cancelled`. `expires_at` is the deadline of the original hold. Once confirmed, the reservation continues to claim its seats past that timestamp. Lookup and cancellation return the reservation fields without the `checkout` object. Manual seat selection is deferred.

### Provider and checkout

The development organization response contains only public provider settings. Server and webhook secrets are never returned.

```json
{"data":{"id":"development","payment_provider":{"id":"development-stripe","provider_key":"stripe","enabled":true,"publishable_key":"pk_test_..."}}}
```

Event responses include the server-owned `ticket_price_cents`. Starting or retrying checkout for an active hold creates or reuses one pending Stripe Checkout Session in Elements mode. The response contains `payment_id`, `session_id`, `client_secret`, server-calculated `amount`, `currency`, and `status`. It never accepts an amount, provider, or credential from the client. The event price is multiplied by the held seat count; the current development Stripe configuration supplies the checkout currency. See [payments setup](payments.md).

The Portal uses Stripe.js Express Checkout Element and Payment Element. A payment return URL only identifies the Checkout Session to reconcile. The browser sends that ID to `POST /api/v1/reservations/:reservation_id/checkout/reconcile` with its guest token or customer bearer token; `GET /api/v1/reservations/:reservation_id/checkout` is read-only. The server verifies the session belongs to the reservation and reconciles its status; only a paid session can confirm an unexpired hold. Stripe webhook events require a valid signature and are processed idempotently. A late payment after expiration is recorded as `late_success` and does not reclaim seats.

## Conflicts and retries

| Status | Example |
| --- | --- |
| `400 Bad Request` | Malformed JSON or missing required idempotency key. |
| `401 Unauthorized` | Missing, invalid, or expired guest token, or missing/invalid/expired customer bearer token. |
| `404 Not Found` | The event or reservation cannot be found or accessed by the caller. |
| `409 Conflict` | No contiguous block fits, a reservation transition is invalid, or an idempotency key is reused with a different request. |
| `429 Too Many Requests` | Guest-session creation exceeds 20 requests per remote IP in one minute. |
| `422 Unprocessable Content` | Quantity is missing, is outside 1–6, or is not a JSON integer. |

- Reservation creation scopes each idempotency key to the Guest, event, and booking parameters. The same key and parameters replay the original successful creation response; a different Guest or changed parameters cannot replay another caller's hold. Use read-only checkout status or the signed-in reservation lookup for current state. Reusing a key with different parameters in the same scope is a conflict. Concurrent requests with the same key must create at most one hold.
- Stripe webhook event IDs are unique and retries do not apply confirmation twice. The session ID, reservation metadata, amount, and currency must match the pending local payment.
- Payment confirmation, cancellation, and expiry leave one consistent reservation state even when they race. Expired holds are released from the database's overlap constraint so allocation can reclaim their seats.
- Reservation allocation and expiry are handled transactionally; active seat overlap and unique pending Stripe payments are protected by database constraints. Guest credentials allow only operations on that Guest's reservations; they do not grant customer-wide reservation access. Customer bearer queries and actions are scoped to the verified token owner and additionally require the relevant OAuth scope.

See the [stack](stack.md) and [browser UI](ui.md) for how this interface sits alongside Rails-rendered pages.
