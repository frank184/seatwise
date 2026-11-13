# Seatwise API specification

> **Implementation status:** V1 health, event, reservation hold/cancellation, development organization/provider, Stripe Checkout Session, checkout reconciliation, and Stripe webhook endpoints are implemented. The customer lookup and sign-in endpoints remain design context; this local prototype trusts its caller.

The Seatwise JSON API exposes event availability, reservation holds, checkout, cancellation and payment confirmation. See the [V1 requirements](requirements.md).

## Conventions

- Routes are prefixed with `/api/v1`. JSON requests with a body use `Content-Type: application/json`.
- Treat identifiers as opaque values. Row IDs are scoped to an event. The order of rows in the availability response is the order used for allocation.
- Seat positions start at 1. `seat_start` and `seat_end` are inclusive.
- Timestamps are UTC ISO 8601 strings. The server determines hold expiry.
- Error responses use `{"error":{"code":"machine_readable_code","message":"Human-readable explanation"}}`.
- Protected customer and checkout requests send the endpoint's required credential as `Authorization: Bearer <token>`. See [auth](auth.md) for credential types and sign-in endpoints.

## Endpoints

| Method and path | Request | Success |
| --- | --- | --- |
| `GET /api/v1/up` | — | `200` with `{"status":"ok","api_version":"v1"}`. |
| `GET /api/v1/events` | — | `200` with `events`, an array of published event summaries ordered by `starts_at` with an ID tie-breaker. |
| `GET /api/v1/events/:event_id` | — | `200` with an event summary including `id`, `name`, `ticket_price_cents`, and `starts_at`. |
| `GET /api/v1/organizations/development` | — | `200` with public, in-memory Stripe provider configuration. |
| `POST /api/v1/reservations` | `{"event_id":42,"quantity":2,"email":"buyer@example.com"}`. Requires an `Idempotency-Key` header. | `201` with the held reservation and server-assigned seats. |
| `DELETE /api/v1/reservations/:id` | — | `200` with the reservation marked cancelled if it was held. |
| `POST /api/v1/reservations/:reservation_id/checkout/session` | Empty JSON object. | `200` with the pending payment, Stripe Checkout Session ID, client secret, amount, and currency. |
| `GET /api/v1/reservations/:reservation_id/checkout?session_id=cs_...` | — | `200` with `processing`, `succeeded`, `failed`, or `expired`, after server-side reconciliation. |
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

The local endpoint requires a guest email and creates or reuses the customer record. Repeating the same event, quantity and email with the same key returns the original reservation with `200`; changing those values while reusing a key returns `409`. Stale held reservations are marked expired during allocation, and the database overlap constraint remains the final guard against concurrent claims.

`status` is one of `held`, `confirmed`, `expired` or `cancelled`. `expires_at` is the deadline of the original hold. Once confirmed, the reservation continues to claim its seats past that timestamp. Lookup and cancellation return the reservation fields without the `checkout` object. Manual seat selection is deferred.

### Provider and checkout

The development organization response contains only public provider settings. Server and webhook secrets are never returned.

```json
{"data":{"id":"development","payment_provider":{"id":"development-stripe","provider_key":"stripe","enabled":true,"publishable_key":"pk_test_..."}}}
```

Event responses include the server-owned `ticket_price_cents`. Starting or retrying checkout for an active hold creates or reuses one pending Stripe Checkout Session in Elements mode. The response contains `payment_id`, `session_id`, `client_secret`, server-calculated `amount`, `currency`, and `status`. It never accepts an amount, provider, or credential from the client. The event price is multiplied by the held seat count; the current development Stripe configuration supplies the checkout currency. See [payments setup](payments.md).

The portal uses Stripe.js Express Checkout Element and Payment Element. A payment return URL only signals that the matching Checkout Session should be retrieved. The server verifies the session belongs to the reservation and reconciles its status; only a paid session can confirm an unexpired hold. Stripe webhook events require a valid signature and are processed idempotently. A late payment after expiration is recorded as `late_success` and does not reclaim seats.

## Conflicts and retries

| Status | Example |
| --- | --- |
| `400 Bad Request` | Malformed JSON or missing required idempotency key. |
| `401 Unauthorized` | Reserved for protected customer API calls; guest checkout in this local prototype currently uses trusted callers. |
| `404 Not Found` | The event or reservation cannot be found or accessed by the caller. |
| `409 Conflict` | No contiguous block fits, a reservation transition is invalid, or an idempotency key is reused with a different request. |
| `422 Unprocessable Content` | Quantity is missing, is outside 1–6, or is not a JSON integer. |

- Reservation creation scopes each key to the event in the trusted local prototype. In customer-facing checkout, scope the key to the customer and event. The same key and booking parameters replay the original successful creation response, including its checkout link and expiry. Use checkout status or the signed-in reservation lookup for current state. Reusing a key with different parameters in the same scope is a conflict. Concurrent requests with the same key must create at most one hold.
- Stripe webhook event IDs are unique and retries do not apply confirmation twice. The session ID, reservation metadata, amount, and currency must match the pending local payment.
- Payment confirmation, cancellation, and expiry leave one consistent reservation state even when they race. Expired holds are released from the database's overlap constraint so allocation can reclaim their seats.
- Reservation allocation and expiry are handled transactionally; active seat overlap and unique pending Stripe payments are protected by database constraints. The local prototype does not yet provide authenticated customer-scoped access.

See the [stack](stack.md) and [browser UI](ui.md) for how this interface sits alongside Rails-rendered pages.
