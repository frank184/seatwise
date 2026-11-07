# Seatwise requirements

V1 is a ticket reservation API. These are the behaviors required for the first version and the features that can wait.

## Must-haves for V1

| Area | Required behavior |
| --- | --- |
| Event layout | A venue has ordered rows with consecutive seat numbers starting at 1. Rows can have different capacities. When an event is published, copy the venue layout into an event snapshot that stays fixed for its bookings. Availability is independent for each event. |
| Availability API | Return the published layout and merged blocked seat ranges by row. Together these let a client show which seats are free without exposing individual bookings. |
| Automatic allocation | Accept a quantity from 1 to 6. Choose adjacent seats in one row, using the frontmost eligible row and then the lowest available starting seat number. Hold the whole group or fail. |
| Valid seat claims | Use the event's stable `row_id` and inclusive, one-based `seat_start` and `seat_end`. Every seat in the requested range must exist in the event layout. |
| No double booking | Two active claims for the same event and row cannot overlap, even when requests arrive concurrently. PostgreSQL enforces this rule for held and confirmed reservations. |
| Temporary holds | A hold claims seats for five minutes. An expired hold cannot be confirmed and its seats must be released for reuse. |
| Reservation lookup | Let the customer retrieve their reservation, including the assigned seats, current status and hold expiry. |
| Payment confirmation | Simulate an external payment provider. A successful payment notification can confirm an unexpired hold. Confirmed reservations keep claiming their seats. |
| Cancellation | Allow cancellation of unconfirmed reservations and release their seats. |
| Safe retries | Retrying the same reservation request must not create another reservation. Duplicate payment notifications must not apply confirmation twice. |

## Customer-facing access

Customers can place a hold and pay as guests using a checkout email. Seatwise sends the booking confirmation and event updates to that address. Customers sign in with an email code to view or cancel their reservations. A session lasts up to 30 days. The local API exercise can use trusted callers. See [auth](auth.md) for checkout and sign-in.

## Nice-to-haves after V1

| Feature | What it would add |
| --- | --- |
| Browser portal | A Rails-rendered seat map and booking flow. See the [browser UI design](ui.md). |
| Saved tickets | Save a confirmed ticket ahead of time and verify its signature at the venue without internet. Wallet delivery is optional. See [offline ticket verification](tickets.md). |
| Manual seat selection | Let the customer submit a specific row and seat range through the same booking rules. |
| Richer venue layouts | Aisles, gaps, accessible and companion seats, and precise map coordinates. |
| Pricing and refunds | Multiple price tiers and refunds for confirmed purchases. |
| Layout management | Layout revision history and a workflow for changing published inventory during sales. |

See [entities and design decisions](entities.md) for the data model, enforcement details and open implementation questions.
