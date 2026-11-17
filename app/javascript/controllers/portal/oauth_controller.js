import { Controller } from "@hotwired/stimulus";
import { fetchJson } from "controllers/portal/view_helpers";

const TRANSACTION_KEY = "seatwise.oauth.transaction";
const TOKEN_KEY = "seatwise.oauth.token";
const API_BASE = "/api/v1";

function base64Url(bytes) {
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function randomValue(length = 32) {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return base64Url(bytes);
}

function safeReturnTo(value) {
  if (
    typeof value !== "string" ||
    !value.startsWith("/") ||
    value.startsWith("//") ||
    value.includes("\\") ||
    /[\u0000-\u001f\u007f]/.test(value)
  ) {
    return "/account/reservations";
  }
  const url = new URL(value, window.location.origin);
  return url.origin === window.location.origin
    ? `${url.pathname}${url.search}${url.hash}`
    : "/account/reservations";
}

function savedToken() {
  try {
    const token = JSON.parse(sessionStorage.getItem(TOKEN_KEY));
    if (token?.access_token && token.expires_at > Date.now()) return token;
  } catch (_) {}
  sessionStorage.removeItem(TOKEN_KEY);
  return null;
}

export default class extends Controller {
  connect() {
    if (this.element.dataset.code !== undefined) this.finishCallback();
    if (
      this.element.dataset.returnTo !== undefined &&
      this.element.dataset.action?.includes("load")
    )
      this.loadReservations();
  }

  async start(event) {
    event?.preventDefault();
    await this.beginAuthorization();
  }

  async beginAuthorization() {
    const state = randomValue();
    const verifier = randomValue(48);
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
    const challenge = base64Url(new Uint8Array(digest));
    const returnTo = safeReturnTo(this.element.dataset.returnTo || window.location.pathname);
    sessionStorage.setItem(
      TRANSACTION_KEY,
      JSON.stringify({ state, verifier, returnTo, createdAt: Date.now() }),
    );

    const authorize = new URL("/oauth/authorize", window.location.origin);
    authorize.search = new URLSearchParams({
      client_id: this.element.dataset.clientId || "",
      redirect_uri: this.element.dataset.redirectUri || `${window.location.origin}/oauth/callback`,
      response_type: "code",
      scope: "reservations:read reservations:manage",
      state,
      code_challenge: challenge,
      code_challenge_method: "S256",
    });
    window.location.assign(authorize.toString());
  }

  async finishCallback() {
    const showError = (message) => {
      const status = document.getElementById("oauth-client-status");
      if (status) status.textContent = message;
    };
    const query = new URLSearchParams(window.location.search);
    const code = this.element.dataset.code || query.get("code");
    const returnedState = this.element.dataset.state || query.get("state");
    window.history.replaceState({}, "", window.location.pathname);
    const rawTransaction = sessionStorage.getItem(TRANSACTION_KEY);
    sessionStorage.removeItem(TRANSACTION_KEY);
    let transaction;
    try {
      transaction = JSON.parse(rawTransaction);
    } catch (_) {}
    if (
      this.element.dataset.oauthError === "true" ||
      !transaction ||
      !code ||
      transaction.state !== returnedState ||
      Date.now() - transaction.createdAt > 10 * 60 * 1000
    ) {
      showError("We could not complete that sign-in. Please start again.");
      return;
    }

    try {
      const response = await fetch("/oauth/token", {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          grant_type: "authorization_code",
          code,
          client_id: this.element.dataset.clientId || "",
          redirect_uri:
            this.element.dataset.redirectUri || `${window.location.origin}/oauth/callback`,
          code_verifier: transaction.verifier,
        }),
      });
      const token = await response.json();
      if (!response.ok || !token.access_token) throw new Error("Token exchange failed");
      sessionStorage.setItem(
        TOKEN_KEY,
        JSON.stringify({ ...token, expires_at: Date.now() + Number(token.expires_in) * 1000 }),
      );
      window.location.replace(safeReturnTo(transaction.returnTo));
    } catch (_) {
      showError("Seatwise could not finish connecting. Please start again.");
    }
  }

  async loadReservations() {
    const token = savedToken();
    if (!token) return this.beginAuthorization();
    try {
      const reservations = await fetchJson(`${API_BASE}/reservations`, {
        headers: { Accept: "application/json", Authorization: `Bearer ${token.access_token}` },
      });
      this.renderReservations(reservations);
    } catch (error) {
      if (error.status === 401) {
        sessionStorage.removeItem(TOKEN_KEY);
        return this.beginAuthorization();
      }
      const status = document.getElementById("oauth-client-status");
      if (status) status.textContent = error.message || "Could not load reservations.";
    }
  }

  async signOut(event) {
    event.preventDefault();
    const token = savedToken();
    sessionStorage.removeItem(TOKEN_KEY);
    sessionStorage.removeItem(TRANSACTION_KEY);
    if (token?.access_token) {
      try {
        await fetch("/oauth/revoke", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            client_id: this.element.dataset.clientId || "",
            token: token.access_token,
          }),
        });
      } catch (_) {
        // The Rails session still signs out if revocation is temporarily unavailable.
      }
    }
    this.element.submit();
  }

  renderReservations(reservations) {
    const list = document.getElementById("reservation-list");
    const status = document.getElementById("oauth-client-status");
    if (!list) return;
    list.replaceChildren();
    if (reservations.length === 0) {
      if (status) status.textContent = "No reservations are associated with this account yet.";
      return;
    }
    if (status) status.textContent = "Your reservations";
    reservations.forEach((reservation) => {
      const item = document.createElement("article");
      item.className = "rounded-box border border-base-300 bg-base-100 p-4";
      const title = document.createElement("h2");
      title.className = "font-semibold";
      title.textContent = `Reservation ${reservation.id}`;
      const detail = document.createElement("p");
      detail.className = "mt-1 text-sm text-base-content/70";
      const quantity = reservation.seat_end - reservation.seat_start + 1;
      detail.textContent = `${reservation.status} · row ${reservation.row_id}, seats ${reservation.seat_start}–${reservation.seat_end} · ${quantity} seat${quantity === 1 ? "" : "s"}`;
      item.append(title, detail);
      list.append(item);
    });
  }
}
