export async function fetchJson(url, options = {}) {
  const response = await fetch(url, {
    headers: { Accept: "application/json", ...options.headers },
    ...options,
  });
  const body = await response.json();
  if (!response.ok) throw new Error(body.error?.message || `Request failed (${response.status})`);
  return body;
}

export function cloneTemplate(root, selector) {
  return root.querySelector(selector).content.firstElementChild.cloneNode(true);
}

export function formatDate(value, options) {
  return new Intl.DateTimeFormat(undefined, options).format(new Date(value));
}
