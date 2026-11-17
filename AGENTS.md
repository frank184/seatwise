# Portal UI conventions

- Before adding or rewriting portal UI markup, inspect `app/helpers/portal/design_system/` and `app/helpers/portal/design_system_helper.rb`. Prefer an existing helper when it represents the component shape, such as `button`, `card`, `card_body`, `card_title`, `badge`, `status_badge`, `status_alert`, `data_table`, or `lucide`.
- Compose helpers inside bespoke view layouts. Keep one-off semantic structure in ERB, but do not rebuild an existing component's root markup and daisyUI classes by hand.
- For model-backed forms, prefer Rails form builders and helpers (`form_with`, `label`, `text_field`, `select`, `check_box`, etc.). Do not add parallel form helpers unless a repeated app-level pattern justifies them. The input-agnostic `field` helper is available for standalone examples.
- Use `lucide` for icons so decorative icons are hidden from assistive technology by default. Mark meaningful icons with an accessible label.
- Follow `.agents/skills/daisyui/SKILL.md` when adding daisyUI or Tailwind markup.

# V1 API boundary

- Treat `/api/v1/*` as a client-neutral JSON contract, as if the Portal were a separate React or mobile application. API controllers must not read or set cookies, depend on Rails sessions, or use Portal-specific Origin/fetch metadata as authentication.
- Send API authentication explicitly in `Authorization`: `Bearer <customer_access_token>` for verified customer operations, or `Guest <guest_token>` for reservations owned by a temporary Guest actor. A reservation ID alone is never authorization.
- `POST /api/v1/guest_sessions` creates a Guest and returns a one-time JSON guest token. Store only its digest in Rails; never put the token in a URL or logs. The Portal may retain it in its own tab session storage or a Portal-owned server session, but must send it to V1 as an explicit header, never as a cookie.
- Portal or client fetches to `/api/v1/*` must omit browser credentials. Use the shared `fetchJson` helper, which enforces this rule.
- OAuth authorization pages and Portal HTML may use the Portal's Rails session. That session is distinct from V1 authentication and must not be forwarded to the API.
