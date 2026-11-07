# Seatwise API specification

> **Implementation status:** This documents the planned V1 contract. Currently, only `GET /api/v1/up` is implemented; the other endpoints below are design context.

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
| `GET /api/v1/events/:event_id` | — | `200` with an event summary containing `id`, `name` and `starts_at`. |
| `GET /api/v1/events/:event_id/availability` | — | `200` with the published rows and their merged blocked ranges. |
| `POST /api/v1/events/:event_id/reservations` | `{"quantity":2,"email":"buyer@example.com"}` for guest checkout. For an authenticated customer, use the credential's customer identity and accept `{"quantity":2}`. Both require an `Idempotency-Key` header. | `201` with the held reservation, a `checkout` object and a `Location` header pointing to the reservation resource. |
| `GET /api/v1/reservations/:id` | Customer bearer token. | `200` with the current reservation representation. |
| `POST /api/v1/reservations/:id/cancellation` | Customer bearer token. Empty body. | `200` with the cancelled reservation. Repeating a successful cancellation returns that same status. |
| `GET /api/v1/reservations/:id/checkout` | Checkout bearer token for this reservation. | `200` with the current checkout status. |
| `POST /api/v1/reservations/:id/checkout/payment` | Checkout bearer token for this reservation. Empty body. | `202` with the checkout status after starting or reusing the pending simulated payment. An already confirmed checkout returns `200` with its current status. |
| `POST /api/v1/payment_notifications` | Simulator credential and `{"notification_id":"pn_123","payment_id":"pay_42","reservation_id":"res_42","outcome":"succeeded"}`. | `200` with `{"disposition":"applied"}`, `{"disposition":"duplicate"}` or `{"disposition":"ignored"}`. An ended hold is acknowledged and left unchanged. |

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

`201 Created` includes `Location: /api/v1/reservations/res_42` and `Cache-Control: no-store`.

```json
{
  "id": "res_42",
  "event_id": "evt_42",
  "row_id": "front_a",
  "seat_start": 5,
  "seat_end": 6,
  "status": "held",
  "expires_at": "2026-11-06T19:05:00Z",
  "checkout": {
    "url": "/checkout/res_42#checkout_example",
    "access_token": "checkout_example",
    "expires_at": "2026-11-06T19:15:00Z"
  }
}
```

`status` is one of `held`, `confirmed`, `expired` or `cancelled`. `expires_at` is the deadline of the original hold. Once confirmed, the reservation continues to claim its seats past that timestamp. Lookup and cancellation return the reservation fields without the `checkout` object. Manual seat selection is deferred.

### Checkout status

Both checkout endpoints return the current state of the reservation and its simulated payment.

```json
{
  "reservation_id": "res_42",
  "reservation_status": "held",
  "hold_expires_at": "2026-11-06T19:05:00Z",
  "payment_id": "pay_42",
  "payment_status": "pending"
}
```

Before payment starts, `payment_id` is `null` and `payment_status` is `not_started`. Starting payment for an active hold creates one simulated payment attempt. Retrying while payment is pending returns the same attempt. A successful notification for that attempt changes the reservation to `confirmed` and payment status to `succeeded`. The browser can poll checkout status while waiting for the outcome.

An expired or cancelled hold returns `409` on payment start. A checkout status read can still report its terminal reservation state while the checkout credential is valid. Checkout never extends the hold deadline. Seatwise sends the booking confirmation once when the reservation is confirmed.

## Conflicts and retries

| Status | Example |
| --- | --- |
| `400 Bad Request` | Malformed JSON or missing required idempotency key. |
| `401 Unauthorized` | A protected request is missing a bearer token, or a supplied token is invalid, expired or revoked. |
| `404 Not Found` | The event or reservation cannot be found or accessed by the caller. |
| `409 Conflict` | No contiguous block fits, a reservation transition is invalid, or an idempotency key is reused with a different request. |
| `422 Unprocessable Content` | Quantity is missing, is outside 1–6, or is not a JSON integer. |

- Reservation creation scopes each key to the event in the trusted local prototype. In customer-facing checkout, scope the key to the customer and event. The same key and booking parameters replay the original successful creation response, including its checkout link and expiry. Use checkout status or the signed-in reservation lookup for current state. Reusing a key with different parameters in the same scope is a conflict. Concurrent requests with the same key must create at most one hold.
- Payment notifications use their own stable `notification_id`. A repeated notification cannot apply confirmation twice. The notification route accepts the simulated `succeeded` outcome and verifies the provider or simulator credential before processing it. The payment ID must belong to the supplied reservation.
- Payment confirmation, cancellation and expiry must leave one consistent reservation state even when they race. Before accepting a payment notification, check the hold deadline. Expired holds must be released from the database's overlap constraint so allocation can reclaim their seats.
- Choose the allocation transaction, expired hold release strategy and idempotency retention window during implementation. The JSON contract describes their observable effects.

See the [stack](stack.md) and [browser UI](ui.md) for how this interface sits alongside Rails-rendered pages.
