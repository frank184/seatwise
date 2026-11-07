# Local development

## Service names

We use `postgres` and `rails`: concrete names for the two tools in this exercise. Role names such as `db` and `api` are equally valid conventions, but are not necessary here. Compose scopes container names to the project; no fixed `container_name` is needed. Both services join the `seatwise` network.

## Rails in WSL, PostgreSQL in Docker

From the project directory, with asdf Ruby selected:

```sh
docker compose up postgres
```

In a second WSL terminal:

```sh
rails s
```

The PostgreSQL image creates `seatwise_development` on its first start. Database migrations are explicit: run `bin/rails db:migrate` only after migration work is ready. Neither app startup nor `bin/setup` migrates or prepares the database automatically. Use `RAILS_ENV=test bin/rails db:migrate` only when the test schema is ready too.

During schema development, Rails skips the development pending-migration page so the API and UI health routes remain available. Database-backed features still require the corresponding schema.

For a detached database that waits for readiness:

```sh
docker compose up -d --wait postgres
```

Rails uses `127.0.0.1:5432` by default. The checked-in development-only username/password match Compose and require no `.env` file or stored secret. Production configuration is separate.

## Both services in Docker

```sh
docker compose up --build
```

Compose waits for PostgreSQL readiness, then starts Rails and the Tailwind watcher through `bin/dev` on port 3000. Startup does not run migrations or prepare the database. The source directory is bind-mounted for development reloading, and Rails runs as UID/GID 1000 to match this WSL user. Rebuild after changing Gemfile/Gemfile.lock or Ruby version.

Check boot health at http://localhost:3000/up. The generated `/up` endpoint checks application boot, not database connectivity.

```sh
docker compose exec rails bin/rails console
docker compose exec postgres psql -U seatwise -d seatwise_development
```

Stop containerized Rails before using WSL Rails on the same port:

```sh
docker compose stop rails
rails s
```

## Storage, ports, and shutdown

- PostgreSQL 18 stores data in the `postgres_data` named volume mounted at `/var/lib/postgresql`.
- Published ports bind only to localhost.
- If 5432 is occupied, `export POSTGRES_PORT=5433` in the WSL terminals running Compose and Rails. Containerized Rails still uses internal port 5432.
- `RAILS_PORT` changes the container's published HTTP port; WSL Rails can use `rails s -p 3001` separately.
- `docker compose down` stops/removes the containers and network but preserves database data.
- `docker compose down -v` also deletes the database volume; use only for an intentional reset.
- Initialization credentials/database settings apply when PostgreSQL initializes an empty volume, not on every restart.

## Generated Rails Dockerfile

The Rails-generated `Dockerfile` targets production, with deployment-mode bundling, development gems excluded, a non-root runtime user, and Thruster in front of the Rails server. `Dockerfile.dev` is a separate, smaller development configuration with development/test gems and a source bind mount. No deployment configuration is needed for this exercise.
