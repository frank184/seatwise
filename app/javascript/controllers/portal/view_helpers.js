import dayjs from "dayjs";
import relativeTime from "dayjs/plugin/relativeTime";

dayjs.extend(relativeTime);

let inMemoryGuestToken = null;
let guestTokenPromise = null;
const PORTAL_ACCESS_TOKEN_KEY = "seatwise.oauth.token";
const GUEST_TOKEN_KEY = "seatwise.guest.token";

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

export async function guestCapabilityToken() {
  return ensureGuestToken();
}

export async function reservationAuthorizationHeader() {
  const customerToken = readPortalAccessToken();
  return customerToken ? `Bearer ${customerToken}` : `Guest ${await ensureGuestToken()}`;
}

export async function fetchReservationJson(url, options = {}) {
  const headers = new Headers(options.headers);
  let authorization = headers.get("Authorization");
  if (!authorization) {
    authorization = await reservationAuthorizationHeader();
    headers.set("Authorization", authorization);
  }

  try {
    return await fetchJson(url, { ...options, headers });
  } catch (failure) {
    if (![401, 403].includes(failure.status)) throw failure;

    if (/^Bearer\s/i.test(authorization)) clearPortalAccessToken();
    else if (/^Guest\s/i.test(authorization)) clearGuestToken();
    else throw failure;

    authorization = `Guest ${await ensureGuestToken()}`;
    headers.set("Authorization", authorization);
    try {
      return await fetchJson(url, { ...options, headers });
    } catch (guestFailure) {
      if (![401, 403].includes(guestFailure.status)) {
        if (isReservationResourceUrl(url) && guestFailure.status === 404) {
          guestFailure.reservationAccessLost = true;
        }
        throw guestFailure;
      }

      clearGuestToken();
      headers.set("Authorization", `Guest ${await ensureGuestToken()}`);
      try {
        return await fetchJson(url, { ...options, headers });
      } catch (refreshedGuestFailure) {
        if (isReservationResourceUrl(url) && refreshedGuestFailure.status === 404) {
          refreshedGuestFailure.reservationAccessLost = true;
        }
        throw refreshedGuestFailure;
      }
    }
  }
}

async function ensureGuestToken() {
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
          sessionStorage.setItem(GUEST_TOKEN_KEY, guestToken);
        } catch (_error) {}
        return guestToken;
      })
      .finally(() => {
        guestTokenPromise = null;
      });
    guestToken = await guestTokenPromise;
  }
  return guestToken;
}

export function readPortalAccessToken() {
  let token;
  try {
    token = JSON.parse(sessionStorage.getItem(PORTAL_ACCESS_TOKEN_KEY));
  } catch (_) {}
  if (token?.access_token && token.expires_at > Date.now()) return token.access_token;
  clearPortalAccessToken();
  return null;
}

export function clearPortalAccessToken() {
  try {
    sessionStorage.removeItem(PORTAL_ACCESS_TOKEN_KEY);
  } catch (_) {}
}

function readGuestToken() {
  try {
    inMemoryGuestToken = sessionStorage.getItem(GUEST_TOKEN_KEY) || inMemoryGuestToken;
  } catch (_error) {}
  return inMemoryGuestToken;
}

function clearGuestToken() {
  inMemoryGuestToken = null;
  try {
    sessionStorage.removeItem(GUEST_TOKEN_KEY);
  } catch (_error) {}
}

function isReservationResourceUrl(url) {
  try {
    return /^\/api\/v1\/reservations\/[^/]+/.test(new URL(url, window.location.origin).pathname);
  } catch (_error) {
    return false;
  }
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
