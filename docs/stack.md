# Seatwise stack

| Layer | Choice |
| --- | --- |
| Application | Ruby 4.0.9 and Rails 8.1.4.1, as pinned in the project |
| Web server | Puma |
| Data | PostgreSQL 18 in local Compose, accessed through Active Record and the `pg` adapter |
| Booking rules | Shared Ruby services for availability, allocation, holds and reservation transitions |
| Browser UI | `Portal`-namespaced Rails controllers and ERB templates in the main app |
| Styling | `tailwindcss-rails` and DaisyUI, built into the Rails asset pipeline |
| Local development | Rails in WSL with PostgreSQL in Docker, or both services in Compose |

## API and HTML routes

Seatwise uses the standard Rails stack for HTML. The API surface remains controller-separated: API controllers inherit from `ActionController::API`, while browser controllers inherit from `ActionController::Base`. Both use the same Rails application and Rack middleware.

| Surface | Routes | Response |
| --- | --- | --- |
| Programmatic API | `/api/v1/...` | JSON with a versioned contract |
| API health | `/api/v1/up` | JSON API process status |
| Browser UI | `/` and `/design-system` | DaisyUI reference page |
| Health check | `/up` | Rails application boot health |

Keep browser controllers, views and routes under the in-app `Portal` namespace. Put JSON endpoints under `Api::V1` and inherit from `Api::V1::BaseController`. HTML actions render templates, while API actions serialize JSON. Browser writes use Rails form protection. Keep API requests stateless; the planned browser-to-API credential exchange is documented in [authentication](auth.md).

The initial page is a component and color reference only. It does not implement event browsing, reservation flows or API-backed interactions.

PostgreSQL arbitrates concurrent seat claims. Ruby code checks a requested seat range against the event's published inventory and handles the booking workflow. See [entities and design decisions](entities.md), the [API specification](api.md), the [UI design](ui.md) and the [local development guide](development.md).
