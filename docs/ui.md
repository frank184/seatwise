# Seatwise browser UI

The planned browser portal uses the [Rails UI stack](stack.md) to show event availability and let customers book seats and manage reservations. The current UI implementation is only a DaisyUI reference palette at `/`; the product pages below remain design direction. Rails renders the pages, and the browser calls the [JSON API](api.md) for booking actions.

## Pages

| Page | What the user sees and does |
| --- | --- |
| `GET /events` | Browse published events by start time. Each entry links to the event page. Include an empty state when no events are listed. |
| `GET /events/:id` | See event details, seat availability and a booking form for 1–6 seats. Display rows in allocation order, with numbered seats and clear labels for available and blocked seats. |
| `GET /reservations/:id` | See the assigned row and seats, reservation status and hold deadline when applicable. The user can refresh the page for current status. |

## Booking flow

1. The user opens an event, reviews the seat map and chooses a quantity. A guest enters an email address.
2. The browser submits the booking form to `POST /api/v1/events/:event_id/reservations`. Seatwise allocates a contiguous block and places a five-minute hold. Checkout shows the assigned seats and deadline while the customer completes payment.
3. When payment confirms the reservation, Seatwise emails a booking reference and a link to manage it. A signed-in customer can view an active hold from the reservation page and cancel it through `POST /api/v1/reservations/:id/cancellation`.

A successful booking request creates a hold immediately. A preview could show a suggested block before a customer places a hold, and availability could change before they submit. Manual seat selection is a later feature.

Guest checkout is available without signing in. Customers use an email code to start a [browser session](auth.md) when they return to manage their reservations. The portal uses that session to obtain a bearer token from a CSRF-protected browser endpoint. The local prototype assumes trusted callers.

## Rendering and interactions

HTML controllers load the initial page data through the same Ruby services used by the API. Vanilla JavaScript submits the booking and cancellation forms to the same-origin JSON endpoints and handles the response. For signed-in API actions, the browser sends `Authorization: Bearer <token>`, reusing the token until it expires. Reuse the same `Idempotency-Key` when retrying a booking submission.

Use ERB partials for the seat map, booking form and status display. Use Tailwind for layout and DaisyUI for controls and status styling. Distinguish available, blocked and assigned seats with text or symbols as well as colour. Use native form inputs with labels, and present errors next to the relevant action.

| Outcome | Browser behavior |
| --- | --- |
| Hold created | Show the assigned seats and deadline in checkout. |
| Quantity invalid | Show a field error and preserve the entered quantity. |
| Seats unavailable or claimed concurrently | Show updated availability and let the user try again. |
| Hold confirmed | Show the reservation as confirmed. |
| Hold cancelled or expired | Show its terminal status and link back to the event for a new booking. |

Expiry and seat ownership come from the server. The rendered map is a snapshot and can be refreshed. The payment provider simulator drives confirmation through its API notification. The portal displays the resulting status.
