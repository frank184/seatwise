# Seatwise

**Event booking and seat reservations for venues with assigned seating.**

[![CI](https://github.com/frank184/seatwise/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/frank184/seatwise/actions/workflows/ci.yml)
![Ruby 4.0.9](https://img.shields.io/badge/Ruby-4.0.9-CC342D?logo=ruby&logoColor=white)
![Rails 8.1.4.1](https://img.shields.io/badge/Rails-8.1.4.1-D30001?logo=rubyonrails&logoColor=white)
![PostgreSQL 18](https://img.shields.io/badge/PostgreSQL-18-4169E1?logo=postgresql&logoColor=white)
![Tailwind CSS](https://img.shields.io/badge/Tailwind_CSS-06B6D4?logo=tailwindcss&logoColor=white)

Seatwise is an early-stage Rails application for an event reservation API and a server-rendered browser experience. PostgreSQL is the system of record for reservation and seat availability rules.

## Project status

The Rails foundation, versioned API health endpoint, and DaisyUI design reference page are in place. Booking endpoints and customer-facing reservation flows are still being built; see the project docs for the intended behavior.

## Run locally

Start Rails and PostgreSQL with Docker Compose:

```sh
docker compose up --build
```

- App: <http://localhost:3000>
- Rails health: <http://localhost:3000/up>
- API health: <http://localhost:3000/api/v1/up>
- Design reference: <http://localhost:3000/design-system>

Startup does not run database migrations. The schema is still being developed; see [local development](docs/development.md) before running database tasks.

## Documentation

- [Local development](docs/development.md)
- [Requirements](docs/requirements.md)
- [Entities and design decisions](docs/entities.md)
- [Application stack and API/UI boundaries](docs/stack.md)
- [Browser UI design](docs/ui.md)
- [JSON API specification](docs/api.md)
- [Authentication](docs/auth.md)
- [Saved tickets and offline verification](docs/tickets.md)
