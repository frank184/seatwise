# Seatwise: entities and design decisions

## Layout and reservations

Use a mutable venue layout as the authoring representation and copy its current layout into an event when the event is published for bookings. Store each layout as structured serialized data (for example, JSON), rather than creating ORM records for every row and seat. The representation may change without changing the booking vocabulary or reservation API.

The event's layout snapshot is the source of truth for the inventory sold by that event. It stays fixed while bookings are accepted. Later edits to the venue layout affect future events, not published events.

Reservations store the event, customer, row identifier, seat range, status, and original hold deadline. The database requires the event, customer, row, range, and status. The seat block is one PostgreSQL `int4range` column and one Ruby `Range` in the model. Integer ranges use lower-inclusive, upper-exclusive bounds: `1...4` represents seats 1, 2, and 3. The documented public API accepts and returns inclusive `seat_start` and `seat_end` values; the API boundary converts those to and from the model range. Status is a Rails string-backed enum (`held`, `confirmed`, `expired`, `cancelled`) with a database default of `held`; there is no PostgreSQL enum or CHECK constraint restricting the allowed status values. A database CHECK requires `hold_expires_at` to be present when status is `held`. For other statuses the column may be NULL. Its value records the original hold deadline and is retained after a transition; status determines whether that deadline is still active. `row_id` identifies a row within the event's inventory. These names describe the booking domain and do not prescribe the backing representation or its internal ordering columns.

The booking service validates that the requested row and every seat in the range exist in the event inventory. PostgreSQL enforces the race-sensitive rule that active reservations for the same event and row cannot overlap. Availability, allocation, and reservation creation all use the same row and seat-number semantics.

```text
Venue
  id
  name                           # STRING, NOT NULL
  layout                         # JSONB, NOT NULL; serialized rows and seat counts; editable template

Event
  id
  venue_id -> Venue              # NOT NULL, foreign key
  name                           # STRING, NOT NULL
  start_time                     # DATETIME, NOT NULL
  end_time                       # DATETIME, NOT NULL
  layout_snapshot                # JSONB, NOT NULL; copy of venue layout at publication; immutable during sale

Reservation
  id
  event_id -> Event              # NOT NULL, foreign key
  customer_id -> Customer        # NOT NULL, foreign key; owner in the customer-facing flow
  row_id                         # INTEGER, NOT NULL; row identifier within this event's inventory
  seat_range                     # INT4RANGE, NOT NULL; finite, nonempty, one-based, at most 6 seats
  status                         # STRING, NOT NULL, default 'held'; Rails enum: held, confirmed, expired, cancelled
  hold_expires_at                # DATETIME, nullable; model requires it while status is held

  CHECK seat_range is finite and nonempty
  CHECK lower(seat_range) >= 1
  CHECK upper(seat_range) - lower(seat_range) <= 6
  CHECK status <> 'held' OR hold_expires_at IS NOT NULL

  EXCLUDE same event + same row + overlapping seat_range
    WHERE status IN ('held', 'confirmed')

  has_many :payments

Customer
  id
  email                          # STRING, NOT NULL, unique index
  email_verified_at              # DATETIME, nullable until first successful verification
  sign_in_code_digest            # STRING, nullable
  sign_in_code_expires_at        # DATETIME, nullable
  sign_in_code_attempts          # INTEGER, NOT NULL, default 0; failed attempts for the active code

  has_many :reservations
  has_many :payments, through: :reservations

Payment
  id
  reservation_id -> Reservation  # NOT NULL, foreign key
  external_id                    # STRING, NOT NULL
  status                         # STRING, NOT NULL
  amount                         # INTEGER, NOT NULL

  belongs_to :reservation
  delegate :customer, to: :reservation
```

The database column is `hold_expires_at`; the documented reservation API calls the returned hold deadline `expires_at`. The API keeps its inclusive `seat_start` and `seat_end` fields and converts them at the boundary to the model's exclusive-upper-bound `seat_range`. The model and database both reject empty or unbounded ranges, ranges starting below seat 1, and ranges larger than six seats. Payments belong to a reservation, and a customer reaches payments through their reservations. A payment has no direct customer foreign key.

The current fixture shape stores `rows` as objects with `row_id`, `label`, `allocation_order`, and `seat_count`. Each event row needs a stable `row_id`, a display label, a deterministic allocation order, and enough seat-count or seat-membership data to validate the requested seat range. A display label such as `A` is not itself the identifier: labels can change or repeat. Seat numbers are one-based and ordered within a row; they need not encode map coordinates or physical seat labels. If the product later needs nonconsecutive seats, seat labels, or per-seat attributes, the interval model may need to change.

The reservation columns used by PostgreSQL's exclusion constraint must be ordinary columns even when the full layout is serialized. The database checks that `seat_range` is finite, nonempty, starts at seat 1 or later, and contains no more than six seats. It also prevents overlapping ranges for the same event and row. The booking service checks membership against the event inventory. Keep layout ordering separate from identity: automatic allocation uses the explicit row order and the lowest eligible seat number, not lexical sorting of `row_id` or display labels.

## Why this is the starting point

- Freezing the event layout keeps seat coordinates stable from the first booking onward.
- Per-seat row records and version-membership tables add schema and lifecycle work. We have not established that their stronger seat-existence enforcement is worth that cost for this exercise.
- Seat membership is validated in one booking-service path against the event snapshot. This assumes reservation writes go through that service.
- Overlapping bookings are different: concurrent requests can both observe a seat as free. PostgreSQL's exclusion constraint protects this invariant even when requests race.
- The database checks seat-range bounds and maximum quantity. The layout lookup itself stays in application code because a normal CHECK constraint cannot inspect the JSON structure as relational data.
- If direct database writers, seat-specific attributes, live layout edits, or stronger referential guarantees become requirements, revisit the representation.

## Reservation and allocation rules

- Customers request 1–6 adjacent seats in one row.
- For automatic allocation, choose the frontmost eligible row, then the leftmost eligible block.
- Claim the entire group atomically or fail.
- Availability is presented from the event layout plus merged blocked ranges, not by exposing reservation records.
- Manual seat selection can be added later; it submits a chosen row and range through the same reservation rules.
- A hold lasts five minutes. Successful payment may confirm only an unexpired hold.
- Confirmed reservations continue claiming seats. Expired or cancelled holds release them.
- Customers can cancel active holds.
- Reservation request retries and repeated payment notifications must not duplicate effects.
- A stored `held` status continues participating in the exclusion constraint after its deadline. Expiry handling must explicitly release it. Expiry versus confirmation concurrency remains to be designed.
- A five-minute business hold is not a five-minute database transaction; external payment work happens outside the short allocation transaction.

## Code responsibilities

- `Venue` owns editable authoring data. `Event` owns its published layout snapshot.
- A booking service coordinates loading event data, validating a requested range, calculating availability or a suggested block, and creating the reservation.
- Availability/allocation calculations should use plain Ruby data and stay independent of ActiveRecord. Models enforce persistence-level rules where suitable; the service handles event-layout membership.
- PostgreSQL arbitrates concurrent conflicting claims through the exclusion constraint.

## Scope

See [project requirements](requirements.md) for the V1 must-haves and deferred features.

## Relational alternative if requirements change

If seat existence must be enforced by foreign keys, or seats acquire individual attributes, use relational event inventory:

```text
Venue
  id
  name
  layout                          # Could remain serialized authoring data

Event
  id
  venue_id -> Venue
  starts_at

EventRow
  id
  event_id -> Event
  allocation_order
  label

EventSeat
  row_id -> EventRow
  seat_number
  PRIMARY KEY (row_id, seat_number)

Reservation
  id
  event_id -> Event
  customer_id -> Customer        # Owner in the customer-facing flow
  row_id -> EventRow
  seat_start
  seat_end
  ...

  FOREIGN KEY (row_id, seat_start) -> EventSeat(row_id, seat_number)
  FOREIGN KEY (row_id, seat_end)   -> EventSeat(row_id, seat_number)
```

This alternative snapshots only the rows and seats an event sells and enables endpoint foreign keys. It would store `seat_start` and `seat_end` to support those foreign keys, then use `int4range(seat_start, seat_end, '[]')` for overlap enforcement; this is a tradeoff specific to the relational alternative. `allocation_order` controls row selection; `label` is presentation data. Endpoint foreign keys prove that the first and last seats exist but do not prove every intervening seat exists or that seat numbers are consecutive. The event/row relationship must also be constrained so a reservation cannot pair an event with another event's row. A richer venue layout editor with reusable versioned relational rows/seats is another option, but requires deciding how revisions and membership are represented; it is not part of the current scope.

## Naming and invariant requirements

- `row_id` is the event-inventory row identity carried by availability, allocation, and reservation records. Its storage type may differ by implementation (for example, a JSON key or a relational primary key), but callers treat it as an opaque identifier.
- `seat_range` is a finite, nonempty, one-based `int4range` of seats in the identified row. PostgreSQL stores integer ranges as lower-inclusive and upper-exclusive; the public API converts its inclusive endpoints at the boundary.
- Do not use a generic `position` field for reservation coordinates. It is ambiguous without naming what is positioned, and it exposes storage mechanics instead of reservation meaning. Use qualified implementation fields such as `allocation_order` and `seat_number` where those concepts are needed.
- A given event's `row_id` values are unique and stable for the lifetime of its published inventory. Copying the venue layout into an event establishes the event's own inventory identity; later venue edits do not mutate it.
- Validate that `seat_range` is finite, nonempty, starts at 1 or later, and contains at most six seats. The booking service also validates row membership and seat bounds against the event layout.
- Prevent overlapping active intervals for the same `(event_id, row_id)` atomically. Expiry and status transitions must release or retain that claim according to the reservation lifecycle.
- Preserve a separate deterministic row allocation order and display label. Neither is a substitute for `row_id`.

## Customer identity and reservation ownership

- A `Customer` has a stable ID and a unique `email`. The record can exist before email verification. Seatwise sets `email_verified_at` on first verification and sends confirmations and event updates to the address provided at checkout.
- A guest hold belongs to the customer identified by the submitted email, even before verification. The authenticated customer's ID controls subsequent reservation lookup and cancellation. HTML pages resolve the customer from the session. The API resolves the customer from a bearer token. The local API exercise can run with trusted callers.
- The `Customer` record stores one active sign-in code at a time. Seatwise consumes it to establish a browser session. Code expiry, session expiry and reservation hold expiry have separate lifecycles. See [auth](auth.md) for the sign-in flow.
- A confirmed reservation can supply the data for a future [offline ticket](tickets.md). The ticket grants admission only.

## Open design questions

- How will the layout JSON encode row identity and allocation order?
- How long should reservation idempotency keys be retained?
- How will allocation release expired holds while protecting against concurrent confirmation?
