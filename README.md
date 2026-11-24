# Seatwise

**Event booking and seat reservations for venues with assigned seating.**

![Ruby 4.0.10](https://img.shields.io/badge/Ruby-4.0.10-CC342D?logo=ruby&logoColor=white)
![Rails 8.1.4.1](https://img.shields.io/badge/Rails-8.1.4.1-D30001?logo=rubyonrails&logoColor=white)
![PostgreSQL 18](https://img.shields.io/badge/PostgreSQL-18-4169E1?logo=postgresql&logoColor=white)
![Tailwind CSS](https://img.shields.io/badge/Tailwind_CSS-06B6D4?logo=tailwindcss&logoColor=white)

Seatwise is a Rails application for discovering events and booking assigned seats. Its browser portal is backed by a versioned JSON API, with PostgreSQL enforcing reservation and seat-availability rules.

## What works today

- Browse upcoming and past events, inspect venue layouts, and view live seat availability.
- Place guest or customer reservations with automatic adjacent-seat allocation and five-minute holds.
- Pay through Stripe test mode; payment confirmation is reconciled through signed webhooks or server-side Stripe checks.
- Sign in with an email code and use PKCE OAuth to view and manage customer reservations.
- Send ticket confirmation emails through a durable, retryable delivery queue.

The project is an active prototype. Production operations, venue management, and downloadable signed tickets are still under development.

## Run locally

Start Rails and PostgreSQL with Docker Compose:

```sh
docker compose up --build
```

- App: <http://localhost:3000>
- Rails health: <http://localhost:3000/up>
- API health: <http://localhost:3000/api/v1/up>
- Design reference: <http://localhost:3000/design>

In a second terminal, prepare the database and load the development showcase data:

```sh
docker compose exec rails bin/rails db:migrate
docker compose exec rails bin/rails db:seed
```

The seed creates a fresh mix of past and upcoming sample events, reservations, and development OAuth clients. Startup does not run migrations or seeds automatically. See [local development](docs/development.md) for WSL and Docker details.

## Documentation

- [Local development](docs/development.md)
- [Requirements](docs/requirements.md)
- [Entities and design decisions](docs/entities.md)
- [Application stack and API/UI boundaries](docs/stack.md)
- [Browser UI design](docs/ui.md)
- [JSON API specification](docs/api.md)
- [Authentication](docs/auth.md)
- [Payments](docs/payments.md)
- [Saved tickets and offline verification](docs/tickets.md)
