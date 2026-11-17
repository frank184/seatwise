import { Controller } from "@hotwired/stimulus";
import { cloneTemplate, fetchJson, formatDate } from "controllers/portal/view_helpers";

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
    this.page = Number(new URLSearchParams(window.location.search).get("page")) || 1;
    this.reservationsLoaded = false;
    this.handleReservationPopState = () => {
      this.page = Number(new URLSearchParams(window.location.search).get("page")) || 1;
      this.syncReservationFiltersFromUrl();
      this.loadReservations();
    };
    if (this.element.dataset.returnTo !== undefined) {
      window.addEventListener("popstate", this.handleReservationPopState);
      this.syncReservationFiltersFromUrl();
    }
    if (this.element.dataset.code !== undefined) this.finishCallback();
    if (this.element.dataset.autostart === "true") this.routeFromStart();
    if (
      this.element.dataset.returnTo !== undefined &&
      this.element.dataset.action?.includes("load")
    )
      this.loadReservations();
  }

  disconnect() {
    window.removeEventListener("popstate", this.handleReservationPopState);
    this.reservationsAbortController?.abort();
    clearInterval(this.reservationHoldTimer);
  }

  async start(event) {
    event?.preventDefault();
    await this.beginAuthorization();
  }

  async routeFromStart() {
    await new Promise((resolve) => window.setTimeout(resolve, 250));
    if (savedToken()) {
      window.location.replace(safeReturnTo(this.element.dataset.returnTo));
      return;
    }
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
      showError("We could not complete the secure connection. Please start again.");
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
        JSON.stringify({
          ...token,
          expires_at: Date.now() + Number(token.expires_in) * 1000,
        }),
      );
      window.location.replace(safeReturnTo(transaction.returnTo));
    } catch (_) {
      showError("Seatwise could not finish connecting. Please start again.");
    }
  }

  async loadReservations() {
    const token = savedToken();
    if (!token) return this.beginAuthorization();
    const list = this.element.querySelector("#reservation-list");
    const empty = this.element.querySelector("#reservation-empty");
    const errorContainer = this.element.querySelector("#reservation-error");
    const pagination = this.element.querySelector("#reservation-pagination");
    const count = this.element.querySelector("#reservation-count");
    this.reservationsAbortController?.abort();
    this.reservationsAbortController = new AbortController();
    const { signal } = this.reservationsAbortController;
    if (list) list.setAttribute("aria-busy", "true");
    errorContainer.hidden = true;
    errorContainer.replaceChildren();
    if (!this.reservationsLoaded) {
      empty.hidden = true;
      list.replaceChildren(cloneTemplate(this.element, "#reservation-loading-template"));
      list.hidden = false;
    }
    const url = new URL(`${API_BASE}/reservations`, window.location.origin);
    const params = new URLSearchParams(window.location.search);
    ["q", "status", "venue_id", "page"].forEach((key) => {
      if (params.has(key)) url.searchParams.set(key, params.get(key));
    });
    url.searchParams.set("page", this.page);
    try {
      const { data: reservations, meta } = await fetchJson(url, {
        signal,
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${token.access_token}`,
        },
      });
      if (signal.aborted) return;
      this.renderReservationVenues(meta.venues || []);
      if (this.page !== meta.page) {
        this.page = meta.page;
        const currentParams = new URLSearchParams(window.location.search);
        if (this.page > 1) currentParams.set("page", this.page);
        else currentParams.delete("page");
        const query = currentParams.toString();
        window.history.replaceState(
          {},
          "",
          `${window.location.pathname}${query ? `?${query}` : ""}`,
        );
      }
      this.reservationsLoaded = true;
      this.renderReservations(reservations, meta);
      count.textContent = `${meta.total_count} ${meta.total_count === 1 ? "reservation" : "reservations"}`;
      this.renderReservationPagination(pagination, meta);
    } catch (requestError) {
      if (requestError.name === "AbortError") return;
      if (requestError.status === 401) {
        sessionStorage.removeItem(TOKEN_KEY);
        return this.beginAuthorization();
      }
      if (!this.reservationsLoaded) {
        list.replaceChildren();
        list.hidden = true;
      }
      errorContainer.hidden = false;
      errorContainer.append(cloneTemplate(this.element, "#reservation-error-template"));
      count.textContent = "Reservations unavailable";
    } finally {
      if (!signal.aborted && list) list.removeAttribute("aria-busy");
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

  renderReservations(reservations, meta) {
    const list = this.element.querySelector("#reservation-list");
    const empty = this.element.querySelector("#reservation-empty");
    if (!list) return;
    clearInterval(this.reservationHoldTimer);
    list.replaceChildren();
    empty.hidden = true;
    if (reservations.length === 0) {
      const emptyCard = cloneTemplate(this.element, "#reservation-empty-template");
      const message = emptyCard.querySelector("[data-reservation-empty-message]");
      const searchParams = new URLSearchParams(window.location.search);
      const hasFilters = Boolean(searchParams.get("q") || searchParams.get("status"));
      if (message && (!hasFilters || meta.total_count > 0)) {
        message.textContent = !hasFilters
          ? "Your bookings will appear here once you reserve a seat."
          : "Try another search or choose a different status filter.";
      }
      empty.replaceChildren(emptyCard);
      empty.hidden = false;
      list.hidden = true;
      return;
    }
    list.hidden = false;
    reservations.forEach((reservation) => {
      const item = cloneTemplate(this.element, "#reservation-card-template");
      const quantity = reservation.seat_end - reservation.seat_start + 1;
      const event = reservation.event;
      item.querySelector("[data-reservation-reference]").textContent =
        `Reservation ${reservation.id}`;
      item.querySelector("[data-reservation-event]").textContent = event.name;
      const time = item.querySelector("[data-reservation-time]");
      time.dateTime = event.starts_at;
      time.textContent = formatDate(event.starts_at, {
        weekday: "short",
        month: "short",
        day: "numeric",
        year: "numeric",
        hour: "numeric",
        minute: "2-digit",
      });
      item.querySelector("[data-reservation-venue]").textContent = event.venue.name;
      const seatDescription =
        quantity === 1
          ? `Seat ${reservation.seat_start}`
          : `Seats ${reservation.seat_start}–${reservation.seat_end} · ${quantity} seats`;
      item.querySelector("[data-reservation-seats]").textContent =
        `Row ${reservation.row_id} · ${seatDescription}`;
      const status = item.querySelector("[data-reservation-status]");
      const statusLabels = {
        held: "On hold",
        confirmed: "Confirmed",
        expired: "Expired",
        cancelled: "Cancelled",
      };
      status.textContent = statusLabels[reservation.status] || reservation.status;
      status.classList.remove("badge-soft");
      const statusClasses = {
        held: ["badge-soft", "badge-warning"],
        confirmed: ["badge-soft", "badge-success"],
        expired: ["badge-soft", "badge-error"],
        cancelled: ["badge-outline", "border-base-content/25", "text-base-content/75"],
      };
      status.classList.add(
        ...(statusClasses[reservation.status] || ["badge-soft", "badge-neutral"]),
      );
      if (reservation.status === "held" && reservation.expires_at) {
        const countdown = item.querySelector("[data-reservation-countdown]");
        countdown.dataset.reservationId = reservation.id;
        countdown.dataset.deadline = reservation.expires_at;
        countdown.hidden = false;
      }
      list.append(item);
    });
    this.startReservationHoldClock();
  }

  renderReservationVenues(venues) {
    const select = this.element.querySelector("[data-reservation-venue-filter]");
    if (!select) return;
    const selectedVenue = new URLSearchParams(window.location.search).get("venue_id") || "";
    select.replaceChildren(new Option("All venues", ""));
    venues.forEach(({ id, name }) => select.add(new Option(name, id)));
    select.value = selectedVenue;
  }

  startReservationHoldClock() {
    clearInterval(this.reservationHoldTimer);
    this.updateReservationHoldCountdowns();
    if (this.element.querySelector("[data-reservation-countdown]:not([hidden])")) {
      this.reservationHoldTimer = window.setInterval(
        () => this.updateReservationHoldCountdowns(),
        1000,
      );
    }
  }

  updateReservationHoldCountdowns() {
    this.expiredReservationIds ||= new Set();
    this.element.querySelectorAll("[data-reservation-countdown]:not([hidden])").forEach((node) => {
      const remaining = Date.parse(node.dataset.deadline) - Date.now();
      const text = node.querySelector("[data-reservation-countdown-text]");
      if (remaining <= 0) {
        node.hidden = true;
        const status = node.closest("article")?.querySelector("[data-reservation-status]");
        if (status) {
          status.textContent = "Expired";
          status.classList.remove("badge-success", "badge-warning", "badge-neutral", "badge-ghost");
          status.classList.add("badge-error");
        }
        const reservationId = node.dataset.reservationId;
        if (!this.expiredReservationIds.has(reservationId)) {
          this.expiredReservationIds.add(reservationId);
          if (!this.reservationExpiryCheckPending) {
            this.reservationExpiryCheckPending = true;
            this.loadReservations().finally(() => {
              this.reservationExpiryCheckPending = false;
            });
          }
        }
        return;
      }

      const totalSeconds = Math.ceil(remaining / 1000);
      const minutes = Math.floor(totalSeconds / 60);
      const seconds = totalSeconds % 60;
      text.textContent = `${minutes}:${String(seconds).padStart(2, "0")} remaining`;
    });
    if (!this.element.querySelector("[data-reservation-countdown]:not([hidden])")) {
      clearInterval(this.reservationHoldTimer);
    }
  }

  renderReservationPagination(pagination, meta) {
    pagination.hidden = meta.total_pages < 2;
    const previous = pagination.querySelector("[data-page-previous]");
    const next = pagination.querySelector("[data-page-next]");
    previous.disabled = !meta.previous_page;
    next.disabled = !meta.next_page;
    pagination
      .querySelectorAll("[data-page-number], [data-page-ellipsis]")
      .forEach((node) => node.remove());

    const pages = [...new Set([1, meta.page - 1, meta.page, meta.page + 1, meta.total_pages])]
      .filter((page) => page > 0 && page <= meta.total_pages)
      .sort((left, right) => left - right);
    let priorPage = 0;
    pages.forEach((page) => {
      if (page - priorPage > 1) {
        const ellipsis = document.createElement("span");
        ellipsis.className = "join-item px-2 text-base-content/50";
        ellipsis.dataset.pageEllipsis = "";
        ellipsis.textContent = "…";
        next.before(ellipsis);
      }
      const button = cloneTemplate(this.element, "#reservation-page-number-template");
      button.dataset.pageNumber = page;
      button.textContent = page;
      button.setAttribute("aria-label", `Page ${page}`);
      button.classList.toggle("btn-primary", page === meta.page);
      button.classList.toggle("btn-active", page === meta.page);
      if (page === meta.page) button.setAttribute("aria-current", "page");
      next.before(button);
      priorPage = page;
    });
  }

  submitReservationFilters(event) {
    event.preventDefault();
    this.applyReservationFilters();
  }

  revealReservationStatusFilter({ currentTarget }) {
    const scroller = currentTarget.closest(".overflow-x-auto");
    const button = currentTarget.getBoundingClientRect();
    const bounds = scroller.getBoundingClientRect();
    if (button.left < bounds.left) scroller.scrollLeft += button.left - bounds.left;
    else if (button.right > bounds.right) scroller.scrollLeft += button.right - bounds.right;
  }

  reservationFilterChanged() {
    this.applyReservationFilters();
  }

  selectReservationStatus({ currentTarget }) {
    const selectedStatus = currentTarget.dataset.reservationStatusFilter;
    this.element.querySelector("#reservation-status-filter").value = selectedStatus;
    this.syncReservationStatusFilterStyles(selectedStatus);
    this.applyReservationFilters();
  }

  syncReservationStatusFilterStyles(selectedStatus) {
    this.element.querySelectorAll("[data-reservation-status-filter]").forEach((button) => {
      const selected = button.dataset.reservationStatusFilter === selectedStatus;
      const activeClasses = button.dataset.reservationStatusActiveClass.split(" ");
      const inactiveClasses = button.dataset.reservationStatusInactiveClass.split(" ");
      button.classList.remove(...activeClasses, ...inactiveClasses);
      button.classList.add(...(selected ? activeClasses : inactiveClasses));
      button.setAttribute("aria-pressed", selected);
    });
  }

  applyReservationFilters() {
    const form = this.element.querySelector("#reservation-filters");
    const params = new URLSearchParams(new FormData(form));
    for (const key of [...params.keys()]) {
      if (params.get(key) === "" || (key === "status" && params.get(key) === "all")) {
        params.delete(key);
      }
    }
    this.page = 1;
    params.delete("page");
    this.pushReservationUrl(params);
    this.loadReservations();
  }

  navigateToReservationPage(page) {
    this.page = page;
    const params = new URLSearchParams(window.location.search);
    if (page > 1) params.set("page", page);
    else params.delete("page");
    this.pushReservationUrl(params);
    this.loadReservations();
  }

  previousReservationPage() {
    this.navigateToReservationPage(this.page - 1);
  }

  nextReservationPage() {
    this.navigateToReservationPage(this.page + 1);
  }

  goToReservationPage({ currentTarget }) {
    this.navigateToReservationPage(Number(currentTarget.dataset.pageNumber));
  }

  retryReservations() {
    this.loadReservations();
  }

  pushReservationUrl(params) {
    const query = params.toString();
    window.history.pushState({}, "", `${window.location.pathname}${query ? `?${query}` : ""}`);
  }

  syncReservationFiltersFromUrl() {
    const params = new URLSearchParams(window.location.search);
    const form = this.element.querySelector("#reservation-filters");
    if (!form) return;
    form.querySelector('[name="q"]').value = params.get("q") || "";
    form.querySelector('[name="status"]').value = params.get("status") || "all";
    form.querySelector('[name="venue_id"]').value = params.get("venue_id") || "";
    const selectedStatus = params.get("status") || "all";
    this.syncReservationStatusFilterStyles(selectedStatus);
  }
}
