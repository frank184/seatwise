# Portal UI conventions

- Before adding or rewriting portal UI markup, inspect `app/helpers/portal/design_system/` and `app/helpers/portal/design_system_helper.rb`. Prefer an existing helper when it represents the component shape, such as `button`, `card`, `card_body`, `card_title`, `badge`, `status_badge`, `status_alert`, `data_table`, or `lucide`.
- Compose helpers inside bespoke view layouts. Keep one-off semantic structure in ERB, but do not rebuild an existing component's root markup and daisyUI classes by hand.
- For model-backed forms, prefer Rails form builders and helpers (`form_with`, `label`, `text_field`, `select`, `check_box`, etc.). Do not add parallel form helpers unless a repeated app-level pattern justifies them. The input-agnostic `field` helper is available for standalone examples.
- Use `lucide` for icons so decorative icons are hidden from assistive technology by default. Mark meaningful icons with an accessible label.
- Follow `.agents/skills/daisyui/SKILL.md` when adding daisyUI or Tailwind markup.
