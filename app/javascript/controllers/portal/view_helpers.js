import dayjs from "dayjs";
import relativeTime from "dayjs/plugin/relativeTime";

dayjs.extend(relativeTime);

let inMemoryGuestToken = null;
let guestTokenPromise = null;

export async function fetchJson(url, options = {}) {
  const headers = new Headers(options.headers);
  if (!headers.has("Accept")) headers.set("Accept", "application/json");
  const isV1ApiRequest = isApiV1Url(url);
  if (isV1ApiRequest && !headers.has("Authorization")) {
    const token = readPortalAccessToken();
    if (token) headers.set("Authorization", `Bearer ${token}`);
  }
  const response = await fetch(url, {
    ...options,
    ...(isV1ApiRequest ? { credentials: "omit" } : {}),
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

export async function guestAuthorizationHeader() {
  if (readPortalAccessToken()) return null;

  let guestToken = readGuestToken();
  if (!guestToken) {
    guestTokenPromise ||= fetchJson("/api/v1/guest_sessions", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    })
      .then((response) => {
        guestToken = response.guest_token;
        inMemoryGuestToken = guestToken;
        try {
          sessionStorage.setItem("seatwise.guest.token", guestToken);
        } catch (_error) {}
        return guestToken;
      })
      .finally(() => {
        guestTokenPromise = null;
      });
    guestToken = await guestTokenPromise;
  }

  return `Guest ${guestToken}`;
}

export function readPortalAccessToken() {
  try {
    const token = JSON.parse(sessionStorage.getItem("seatwise.oauth.token"));
    if (token?.access_token && token.expires_at > Date.now()) return token.access_token;
  } catch (_) {}
  sessionStorage.removeItem("seatwise.oauth.token");
  return null;
}

function readGuestToken() {
  try {
    inMemoryGuestToken = sessionStorage.getItem("seatwise.guest.token") || inMemoryGuestToken;
  } catch (_error) {}
  return inMemoryGuestToken;
}

function isApiV1Url(url) {
  try {
    return new URL(url, window.location.origin).pathname.startsWith("/api/v1/");
  } catch (_error) {
    return false;
  }
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
