import dayjs from "dayjs";
import relativeTime from "dayjs/plugin/relativeTime";

dayjs.extend(relativeTime);

export async function fetchJson(url, options = {}) {
  const headers = new Headers(options.headers);
  if (!headers.has("Accept")) headers.set("Accept", "application/json");
  if (typeof url === "string" && url.startsWith("/api/v1/") && !headers.has("Authorization")) {
    const token = readPortalAccessToken();
    if (token) headers.set("Authorization", `Bearer ${token}`);
  }
  const response = await fetch(url, {
    ...options,
    headers,
  });
  const body = await response.json();
  if (!response.ok) {
    const error = new Error(body.error?.message || `Request failed (${response.status})`);
    error.status = response.status;
    error.code = body.error?.code;
    throw error;
  }
  return body;
}

export function readPortalAccessToken() {
  try {
    const token = JSON.parse(sessionStorage.getItem("seatwise.oauth.token"));
    if (token?.access_token && token.expires_at > Date.now()) return token.access_token;
  } catch (_) {}
  sessionStorage.removeItem("seatwise.oauth.token");
  return null;
}

export function cloneTemplate(root, selector) {
  return root.querySelector(selector).content.firstElementChild.cloneNode(true);
}

export function formatDate(value, options) {
  return new Intl.DateTimeFormat(undefined, options).format(new Date(value));
}

export function formatRelativeTime(value) {
  if (value == null || value === "") return "";

  const date = dayjs(value);
  return date.isValid() ? date.fromNow() : "";
}
