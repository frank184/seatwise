# Seatwise API specification

> **Implementation status:** V1 health, public event reads, guest-cart creation, guest-scoped reservation hold/cancellation, guest checkout, development organization/provider, Stripe Checkout Session/reconciliation, and Stripe webhook endpoints are implemented. OAuth customer sign-in and customer-scoped reservation lookup remain planned.

The Seatwise JSON API exposes event availability, reservation holds, checkout, cancellation and payment confirmation. See the [V1 requirements](requirements.md).

## Conventions

- Routes are prefixed with `/api/v1`. JSON requests with a body use `Content-Type: application/json`.
- Treat identifiers as opaque values. Row IDs are scoped to an event. The order of rows in the availability response is the order used for allocation.
- Seat positions start at 1. `seat_start` and `seat_end` are inclusive.
- Timestamps are UTC ISO 8601 strings. The server determines hold expiry.
- Error responses use `{"error":{"code":"machine_readable_code","message":"Human-readable explanation"}}`.
- Event reads are public. Guest reservation and checkout operations require a guest-cart capability: the Portal uses an HttpOnly cookie; direct API clients use `Authorization: Guest <secret>`. OAuth customer bearer access is a planned layer; see [auth](auth.md) for the design boundary.

## Endpoints

| Method and path | Request | Success |
| --- | --- | --- |
| `GET /api/v1/up` | — | `200` with `{"status":"ok","api_version":"v1"}`. |
| `GET /api/v1/events` | — | `200` with `events`, an array of published event summaries ordered by `starts_at` with an ID tie-breaker. |
| `GET /api/v1/events/:event_id` | — | `200` with an event summary including `id`, `name`, `ticket_price_cents`, and `starts_at`. |
| `GET /api/v1/organizations/development` | — | `200` with public, in-memory Stripe provider configuration. |
| `POST /api/v1/guest_sessions` | `{"transport":"cookie"}` for the Portal or `{"transport":"body"}` for a direct API client. | `201` creates a guest cart; cookie transport sets an HttpOnly cookie, body transport returns its secret once. An existing valid Portal cookie returns `200` without rotating it. |
| `POST /api/v1/reservations` | `{"event_id":42,"quantity":2,"email":"buyer@example.com"}`. Requires a guest-cart credential and `Idempotency-Key` header. | `201` with the held reservation and server-assigned seats. |
| `DELETE /api/v1/reservations/:id` | Requires the guest-cart credential associated with the hold. | `200` with the reservation marked cancelled if it was held. |
| `POST /api/v1/reservations/:reservation_id/checkout/session` | Empty JSON object; requires the guest-cart credential associated with the hold. | `200` with the pending payment, Stripe Checkout Session ID, client secret, amount, and currency. |
| `GET /api/v1/reservations/:reservation_id/checkout?session_id=cs_...` | Requires the guest-cart credential associated with the hold. Reads locally persisted status only. | `200` with `processing`, `succeeded`, `failed`, or `expired`; does not contact Stripe or change payment/reservation state. |
| `POST /api/v1/reservations/:reservation_id/checkout/reconcile` | `{"session_id":"cs_..."}`; requires the guest-cart credential associated with the hold. | `200` with the reconciled checkout status after retrieving the session from Stripe. |
| `POST /api/v1/payment_webhooks/stripe` | Stripe raw event body and `Stripe-Signature` header. | `200` after supported signed event processing; invalid signatures return `400`. |

### Availability response

```json
{
  "event_id": "evt_42",
  "rows": [
    {
      "row_id": "front_a",
      "label": "A",
      "seat_count": 10,
      "blocked_ranges": [
        { "seat_start": 1, "seat_end": 4 },
        { "seat_start": 7, "seat_end": 8 }
      ]
    }
  ]
}
```

Blocked ranges are sorted, with touching or overlapping intervals merged. They represent confirmed reservations and unexpired holds. Availability can change between this read and the hold request. For this example a request for two seats would be allocated seats 5–6 if the inventory stays the same.

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

Guest reservation creation requires either the Portal's guest-cart cookie or a direct client's `Authorization: Guest <secret>` capability, plus a guest email. The cookie is issued by `POST /api/v1/guest_sessions` and stored server-side as a digest. Cookie-transport bootstrap and cookie-authenticated unsafe requests require the configured Portal `Origin`; cross-site requests are rejected. Body-transport secrets are returned only once and must not be sent to the Portal. The email is reservation contact data, not proof of customer identity.

Repeating the same event, quantity, email and guest cart with the same `Idempotency-Key` returns the original reservation with `200`; changing those values or using the key from another guest cart returns `409`. A different or missing guest credential cannot continue the hold. Stale held reservations are marked expired during allocation, and the database overlap constraint remains the final guard against concurrent claims.

`status` is one of `held`, `confirmed`, `expired` or `cancelled`. `expires_at` is the deadline of the original hold. Once confirmed, the reservation continues to claim its seats past that timestamp. Lookup and cancellation return the reservation fields without the `checkout` object. Manual seat selection is deferred.

### Provider and checkout

The development organization response contains only public provider settings. Server and webhook secrets are never returned.

```json
{"data":{"id":"development","payment_provider":{"id":"development-stripe","provider_key":"stripe","enabled":true,"publishable_key":"pk_test_..."}}}
```

Event responses include the server-owned `ticket_price_cents`. Starting or retrying checkout for an active hold creates or reuses one pending Stripe Checkout Session in Elements mode. The response contains `payment_id`, `session_id`, `client_secret`, server-calculated `amount`, `currency`, and `status`. It never accepts an amount, provider, or credential from the client. The event price is multiplied by the held seat count; the current development Stripe configuration supplies the checkout currency. See [payments setup](payments.md).

The Portal uses Stripe.js Express Checkout Element and Payment Element. A payment return URL only identifies the Checkout Session to reconcile. The browser sends that ID to the origin-checked `POST /api/v1/reservations/:reservation_id/checkout/reconcile` route; `GET /api/v1/reservations/:reservation_id/checkout` is read-only. The server verifies the session belongs to the reservation and reconciles its status; only a paid session can confirm an unexpired hold. Stripe webhook events require a valid signature and are processed idempotently. A late payment after expiration is recorded as `late_success` and does not reclaim seats.

## Conflicts and retries

| Status | Example |
| --- | --- |
| `400 Bad Request` | Malformed JSON or missing required idempotency key. |
| `401 Unauthorized` | Missing, invalid, expired, or wrong guest-cart credential. |
| `403 Forbidden` | Cookie-authenticated mutation has a missing or disallowed Portal `Origin`. |
| `404 Not Found` | The event or reservation cannot be found or accessed by the caller. |
| `409 Conflict` | No contiguous block fits, a reservation transition is invalid, or an idempotency key is reused with a different request. |
| `422 Unprocessable Content` | Quantity is missing, is outside 1–6, or is not a JSON integer. |

- Reservation creation scopes each idempotency key to the guest cart, event, and booking parameters. The same key and parameters replay the original successful creation response; a different guest cart or changed parameters cannot replay another caller's hold. Use read-only checkout status or the signed-in reservation lookup for current state. Reusing a key with different parameters in the same scope is a conflict. Concurrent requests with the same key must create at most one hold.
- Stripe webhook event IDs are unique and retries do not apply confirmation twice. The session ID, reservation metadata, amount, and currency must match the pending local payment.
- Payment confirmation, cancellation, and expiry leave one consistent reservation state even when they race. Expired holds are released from the database's overlap constraint so allocation can reclaim their seats.
- Reservation allocation and expiry are handled transactionally; active seat overlap and unique pending Stripe payments are protected by database constraints. Guest-cart credentials allow only operations on that cart's reservations; they do not grant customer-wide reservation access. OAuth customer-scoped access is not implemented yet.

See the [stack](stack.md) and [browser UI](ui.md) for how this interface sits alongside Rails-rendered pages.
