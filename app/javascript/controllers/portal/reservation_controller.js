import { Controller } from "@hotwired/stimulus";
import { cloneTemplate, fetchJson, formatDate } from "controllers/portal/view_helpers";

const STEP_NUMBERS = { seats: 1, payment: 2, redirecting: 2, confirmed: 3, expired: 1 };

export default class extends Controller {
  connect() {
    this.selectedSeats = new Set();
    this.flow = this.readFlow();
    this.selectedSeats = new Set(this.flow.selectedSeats);
    if (this.flow.reservation?.status === "held") {
      this.element.dataset.availabilityDeadline = String(this.flow.reservation.expiresAt);
    }
    this.availabilityBusy = false;
    this.paymentConfiguration = null;
    this.checkoutSetupWaiters = new Map();
    this.checkoutLoadPromise = null;
    this.availabilityRefreshWaiters = new Map();
    this.conflictRefreshPending = false;
    this.conflictRefreshRequestId = null;
    this.conflictRefreshRecoveryAllowed = false;
    this.reconciliationRequired = false;
    this.selectionReady = false;
    this.beginEventLoad();
  }

  disconnect() {
    clearInterval(this.holdTimer);
    this.resolveCheckoutSetupWaiters(false);
    this.dispatchCheckout("checkout-reset");
  }

  get storageKey() {
    return `seatwise:reservation:${this.element.dataset.eventId}`;
  }

  readFlow() {
    try {
      const stored = JSON.parse(sessionStorage.getItem(this.storageKey));
      if (stored && Array.isArray(stored.selectedSeats)) {
        const flow = { step: "seats", request: null, reservation: null, ...stored };
        if (flow.step === "email") {
          flow.step = "seats";
          if (!["held", "confirmed"].includes(flow.reservation?.status)) {
            flow.furthestStep = STEP_NUMBERS.seats;
            flow.showTimeline = false;
          }
        }
        if (flow.step === "payment") flow.furthestStep = Math.min(flow.furthestStep || 2, 2);
        if (
          flow.step === "seats" &&
          flow.selectedSeats.length === 0 &&
          !["held", "confirmed"].includes(flow.reservation?.status)
        ) {
          flow.showTimeline = false;
          flow.furthestStep = STEP_NUMBERS.seats;
        }
        flow.furthestStep = Math.max(
          flow.furthestStep || 1,
          STEP_NUMBERS[flow.step] || STEP_NUMBERS.seats,
        );
        return flow;
      }
    } catch (_error) {
      // Storage can be disabled by the browser; the flow still works in memory.
    }
    return { step: "seats", selectedSeats: [], request: null, reservation: null };
  }

  saveFlow() {
    this.flow.selectedSeats = [...this.selectedSeats];
    this.flow.furthestStep = Math.max(
      this.flow.furthestStep || 1,
      STEP_NUMBERS[this.flow.step] || STEP_NUMBERS.seats,
    );
    try {
      sessionStorage.setItem(this.storageKey, JSON.stringify(this.flow));
    } catch (_error) {
      // Keep the current flow usable if the browser blocks session storage.
    }
  }

  beginEventLoad() {
    const loading = this.element.querySelector("#event-loading");
    const content = this.element.querySelector("#event-content");
    const error = this.element.querySelector("#event-error");
    loading.hidden = false;
    loading.classList.remove("hidden");
    content.hidden = true;
    error.hidden = true;
    error.replaceChildren();
  }

  applyAvailabilitySnapshot({ detail }) {
    const { event, requestIds = [] } = detail;
    const conflictRefreshSucceeded =
      this.conflictRefreshPending &&
      (requestIds.includes(this.conflictRefreshRequestId) ||
        (this.conflictRefreshRecoveryAllowed && requestIds.length === 0));
    const content = this.element.querySelector("#event-content");
    const loading = this.element.querySelector("#event-loading");
    const error = this.element.querySelector("#event-error");
    this.event = event;
    if (conflictRefreshSucceeded) {
      this.conflictRefreshPending = false;
      this.conflictRefreshRequestId = null;
      this.conflictRefreshRecoveryAllowed = false;
      this.reconciliationRequired = false;
    } else if (!this.conflictRefreshPending) {
      this.reconciliationRequired = false;
    }
    this.selectionReady = false;

    if (this.flow.reservation?.status === "held" && this.flow.reservation.expiresAt <= Date.now()) {
      this.expiryPending = true;
    }

    if (this.expiryPending && this.flow.reservation?.status === "held") {
      this.flow.reservation.status = "expired";
      this.flow.step = "expired";
      this.flow.payment = null;
      this.flow.paymentSession = null;
      this.selectedSeats.clear();
      this.saveFlow();
      clearInterval(this.holdTimer);
      this.expiryPending = false;
      delete this.element.dataset.availabilityDeadline;
    }

    this.renderEventDetails(content, event);
    this.renderReservationEventDetails(event);
    this.updateSelectionSummary();
    this.setAvailabilityPending(this.conflictRefreshPending);
    this.renderFlow();
    content.hidden = false;
    loading.hidden = true;
    loading.classList.add("hidden");
    error.hidden = true;
    error.replaceChildren();
    document.title = `${event.name} · Seatwise`;
    this.startHoldClock();

    requestIds.forEach((requestId) => this.resolveAvailabilityRefresh(requestId, true));
    if (this.initialSnapshotApplied) return;
    this.initialSnapshotApplied = true;

    const checkoutSessionId = new URLSearchParams(window.location.search).get("session_id");
    if (checkoutSessionId) {
      this.restoreCheckoutReturn(checkoutSessionId);
    } else if (
      !this.expiryPending &&
      this.flow.step === "payment" &&
      this.flow.reservation?.status === "held"
    ) {
      this.loadCheckout();
    } else if (
      !this.expiryPending &&
      this.flow.step === "redirecting" &&
      this.flow.reservation?.status === "held"
    ) {
      const sessionId = this.flow.paymentSession?.session_id;
      if (sessionId) this.pollCheckoutStatus(sessionId);
    }
  }

  availabilityRefreshFailed({ detail }) {
    const { error: failure, requestIds = [] } = detail;
    if (this.conflictRefreshPending && requestIds.includes(this.conflictRefreshRequestId)) {
      this.conflictRefreshRequestId = null;
      this.conflictRefreshRecoveryAllowed = true;
      this.reconciliationRequired = true;
      this.selectionReady = false;
    }
    requestIds.forEach((requestId) => this.resolveAvailabilityRefresh(requestId, false));
    const error = this.element.querySelector("#event-error");
    const loading = this.element.querySelector("#event-loading");
    error.replaceChildren();
    error.append(
      cloneTemplate(
        this.element,
        failure.status === 404 ? "#event-not-found-template" : "#event-error-template",
      ),
    );
    error.hidden = false;
    loading.hidden = true;
    loading.classList.add("hidden");
    if (!this.expiryPending && !this.reconciliationRequired) {
      this.setAvailabilityPending(false);
    }
  }

  availabilityRefreshStarted() {
    this.setAvailabilityPending(true);
  }

  setAvailabilityPending(pending) {
    this.availabilityBusy = pending;
    this.syncSeatMapState();
    this.updateHoldSubmitState();
  }

  syncSeatMapState() {
    const mapElement = this.element.querySelector("[data-seat-map]");
    if (!mapElement) return;
    const seatMap = this.application.getControllerForElementAndIdentifier(
      mapElement,
      "portal--seat-map",
    );
    seatMap?.updateState({
      event: this.event,
      selectedSeats: [...this.selectedSeats],
      reservation: this.flow.reservation,
      busy: this.availabilityBusy,
      holdPending: this.flow.request?.status === "pending",
    });
  }

  handleSeatMapSnapshotReconciled({ detail: { requestIds = [] } = {} }) {
    if (
      this.conflictRefreshPending &&
      (!this.conflictRefreshRequestId || !requestIds.includes(this.conflictRefreshRequestId))
    )
      return;
    this.selectionReady = true;
    this.saveFlow();
    this.updateHoldSubmitState();
  }

  handleSeatMapSelectionChanged({ detail }) {
    if (this.flow.request?.status === "pending") return;
    const availabilityInvalidation =
      detail.reason === "availability_changed" && detail.selectedSeats.length === 0;
    if (
      !this.event ||
      (this.availabilityBusy && !availabilityInvalidation) ||
      ["held", "confirmed"].includes(this.flow.reservation?.status)
    ) {
      this.syncSeatMapState();
      return;
    }

    const requestedSeats = new Set(detail.selectedSeats);
    if (requestedSeats.size > 6) {
      this.announce("You can select up to 6 seats.");
      this.syncSeatMapState();
      return;
    }

    const unavailableSeats = new Set(
      this.event.rows.flatMap((row) =>
        row.reserved_seats.map((number) => this.seatKey(row.row_id, number)),
      ),
    );
    if ([...requestedSeats].some((seat) => unavailableSeats.has(seat))) {
      this.syncSeatMapState();
      return;
    }

    const changed =
      requestedSeats.size !== this.selectedSeats.size ||
      [...requestedSeats].some((seat) => !this.selectedSeats.has(seat));
    if (!changed) return;

    if (this.flow.step === "expired" && requestedSeats.size > 0) {
      this.flow.step = "seats";
      this.flow.furthestStep = STEP_NUMBERS.seats;
      this.flow.showTimeline = true;
      this.flow.reservation = null;
      this.flow.request = null;
      this.flow.payment = null;
      this.flow.paymentSession = null;
    }
    this.selectedSeats = requestedSeats;
    if (this.flow.step === "seats" && requestedSeats.size === 0) {
      this.flow.showTimeline = false;
      this.flow.furthestStep = STEP_NUMBERS.seats;
    }
    if (this.flow.request?.status === "failed") this.flow.request.idempotencyKey = null;
    this.saveFlow();
    this.updateSelectionSummary();
    this.renderFlow();
    this.syncSeatMapState();
    if (detail.reason === "availability_changed") {
      this.announce("Selected seats are no longer available. Choose available seats to continue.");
    }
  }

  requestAvailabilityRefresh(detail = {}) {
    const requestId = crypto.randomUUID();
    if (this.conflictRefreshPending) this.conflictRefreshRequestId = requestId;
    const promise = new Promise((resolve) =>
      this.availabilityRefreshWaiters.set(requestId, resolve),
    );
    this.dispatch("refresh-availability", { detail: { ...detail, requestId } });
    return promise;
  }

  resolveAvailabilityRefresh(requestId, succeeded) {
    const resolve = this.availabilityRefreshWaiters.get(requestId);
    if (!resolve) return;
    this.availabilityRefreshWaiters.delete(requestId);
    resolve(succeeded);
  }

  clearHoldError() {
    const error = this.element.querySelector("[data-hold-error]");
    if (error) {
      error.hidden = true;
      error.textContent = "";
    }
  }

  renderEventDetails(content, event) {
    content.querySelector("[data-detail-date]").textContent = formatDate(event.starts_at, {
      weekday: "long",
      month: "long",
      day: "numeric",
    });
    content.querySelector("[data-detail-name]").textContent = event.name;
    content.querySelector("[data-detail-venue]").textContent = event.venue.name;
    content.querySelector("[data-detail-start]").textContent = formatDate(event.starts_at, {
      hour: "numeric",
      minute: "2-digit",
    });
    content.querySelector("[data-detail-end]").textContent = formatDate(event.ends_at, {
      hour: "numeric",
      minute: "2-digit",
    });
    content.querySelector("[data-detail-seats]").textContent = `${event.seat_count} seats`;
    this.updateAvailabilityPresentation(event.available_count);
  }

  updateAvailabilityPresentation(available) {
    const count = this.element.querySelector("[data-detail-open]");
    const availabilityNotice = this.element.querySelector("[data-availability-change-notice]");
    const soldOutNotice = this.element.querySelector("[data-sold-out-notice]");
    const isSoldOut = Number(available) === 0;

    if (count) {
      count.textContent = `${available} seats`;
      count.classList.toggle("text-success", !isSoldOut);
      count.classList.toggle("text-base-content/55", isSoldOut);
    }
    if (availabilityNotice) availabilityNotice.hidden = isSoldOut;
    if (soldOutNotice) soldOutNotice.hidden = !isSoldOut;
  }

  renderReservationEventDetails(event) {
    const date = formatDate(event.starts_at, {
      weekday: "long",
      month: "long",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
    });
    this.element.querySelectorAll("[data-reservation-event]").forEach((node) => {
      node.textContent = event.name;
    });
    this.element.querySelectorAll("[data-reservation-date]").forEach((node) => {
      node.textContent = date;
    });
    this.element.querySelectorAll("[data-reservation-venue]").forEach((node) => {
      node.textContent = event.venue.name;
    });
  }

  seatKey(rowId, number) {
    return `${rowId}:${number}`;
  }

  updateSelectionSummary() {
    const count = this.selectedSeats.size;
    const countText = this.element.querySelector("[data-selection-count]");
    const reservation = this.flow.reservation;
    const held = reservation?.status === "held";
    const confirmed = reservation?.status === "confirmed";
    const countDescription = held
      ? `${reservation.seats.length} ${reservation.seats.length === 1 ? "seat" : "seats"} held for five minutes`
      : confirmed
        ? `${reservation.seats.length} ${reservation.seats.length === 1 ? "seat" : "seats"} confirmed`
        : count
          ? `${count} of 6 seats selected`
          : "Click or drag across up to 6 open seats.";
    const selectedRange = this.selectedSeatRange();
    const reservationStatus = this.element.querySelector("[data-selection-reservation-status]");
    const reservationComplete = held || confirmed;
    reservationStatus.hidden = !reservationComplete;
    reservationStatus.textContent = confirmed ? "Booking confirmed" : "Seats held";
    const selectionMessage = this.element.querySelector("[data-selection-message]");
    selectionMessage.textContent =
      count > 0 && !selectedRange
        ? "Choose up to 6 adjacent seats in the same row to continue."
        : "";
    const summarySeats = reservationComplete ? reservation.seats : this.selectedSeatDetails();
    countText.textContent = countDescription;
    this.element.querySelector("[data-selection-accessible-summary]").textContent =
      summarySeats.length ? this.formatSeatSummary(summarySeats) : "";
    this.renderSelectionVisual(summarySeats);
    this.element.querySelectorAll("[data-seat-summary]").forEach((node) => {
      node.textContent = this.formatSeatSummary(summarySeats);
    });
  }

  renderSelectionVisual(seats) {
    const preview = this.element.querySelector("[data-selection-visual]");
    preview.replaceChildren();
    preview.hidden = seats.length === 0;

    const rows = new Map();
    seats.forEach((seat) => {
      const rowId = String(seat.rowId);
      if (!rows.has(rowId)) rows.set(rowId, []);
      rows.get(rowId).push(Number(seat.number));
    });

    rows.forEach((numbers, rowId) => {
      const row = this.event.rows.find((item) => String(item.row_id) === rowId);
      const group = document.createElement("div");
      group.className = "flex items-center gap-1";

      const label = document.createElement("span");
      label.className = "badge badge-neutral badge-sm whitespace-nowrap px-3";
      label.textContent = `Row ${row?.label || rowId}`;
      group.append(label);

      numbers
        .sort((left, right) => left - right)
        .forEach((number) => {
          const seat = document.createElement("span");
          seat.className =
            "flex size-6 items-center justify-center rounded-t-full border border-primary bg-primary text-[0.625rem] font-semibold tabular-nums text-primary-content";
          seat.textContent = String(number);
          group.append(seat);
        });

      preview.append(group);
    });
  }

  saveEmail({ currentTarget }) {
    const email = currentTarget.value.trim();
    if (this.flow.email !== email && this.flow.request?.status === "failed") {
      this.flow.request.idempotencyKey = null;
    }
    this.flow.email = email;
    this.saveFlow();
    this.updateHoldSubmitState();
  }

  selectedSeatDetails() {
    return [...this.selectedSeats].map((key) => {
      const [rowId, seatNumber] = key.split(":");
      const row = this.event.rows.find((item) => String(item.row_id) === rowId);
      return { rowId, rowLabel: row?.label || rowId, number: Number(seatNumber) };
    });
  }

  selectedSeatRange() {
    if (this.selectedSeats.size < 1 || this.selectedSeats.size > 6) return null;
    const seats = this.selectedSeatDetails().sort((left, right) => left.number - right.number);
    if (seats.some((seat) => seat.rowId !== seats[0].rowId)) return null;
    if (seats.some((seat, index) => index > 0 && seat.number !== seats[index - 1].number + 1))
      return null;
    return {
      rowId: Number(seats[0].rowId),
      seatStart: seats[0].number,
      seatEnd: seats[seats.length - 1].number,
    };
  }

  formatSeatSummary(seats) {
    if (!seats.length) return "No seats selected";
    const rows = [...new Set(seats.map((seat) => String(seat.rowId)))];
    return rows
      .map((rowId) => {
        const row = this.event.rows.find((item) => String(item.row_id) === rowId);
        const numbers = seats
          .filter((seat) => String(seat.rowId) === rowId)
          .map((seat) => seat.number)
          .sort((left, right) => left - right);
        const ranges = [];
        for (const number of numbers) {
          const previous = ranges[ranges.length - 1];
          if (previous && number === previous.end + 1) previous.end = number;
          else ranges.push({ start: number, end: number });
        }
        const labels = ranges.map(({ start, end }) =>
          start === end ? `${start}` : `${start}–${end}`,
        );
        return `Row ${row?.label || rowId} · seats ${labels.join(", ")}`;
      })
      .join(" · ");
  }

  announce(message) {
    this.element.querySelector("[data-selection-message]").textContent = message;
  }

  async navigateToStep(event) {
    const step = event.currentTarget.dataset.flowStep;
    if (!this.canNavigateToStep(step)) return;

    if (step === "seats" && this.flow.reservation?.status === "held") {
      this.requestReleaseHoldConfirmation();
      return;
    }

    this.flow.step = step;
    this.flow.showTimeline = true;
    this.saveFlow();
    this.renderFlow();
    this.updateSelectionSummary();
    if (
      step === "payment" &&
      this.flow.reservation?.status === "held" &&
      !this.paymentConfiguration
    ) {
      await this.loadCheckout();
    }
  }

  canNavigateToStep(step) {
    const targetStep = STEP_NUMBERS[step];
    const furthestStep = Math.max(
      this.flow.furthestStep || 1,
      STEP_NUMBERS[this.flow.step] || STEP_NUMBERS.seats,
    );
    return (
      targetStep &&
      targetStep <= furthestStep &&
      (step !== "payment" || this.flow.reservation?.status === "held") &&
      !["confirmed", "expired", "redirecting"].includes(this.flow.step)
    );
  }

  retry() {
    if (!this.event) this.beginEventLoad();
    this.requestAvailabilityRefresh();
  }

  async placeHold(event) {
    event.preventDefault();
    if (
      this.flow.request?.status === "pending" ||
      !this.selectionReady ||
      this.availabilityBusy ||
      this.reconciliationRequired
    )
      return;
    const form = event.currentTarget;
    const email = form.querySelector("[name=email]").value.trim();
    const selectedRange = this.selectedSeatRange();
    if (!selectedRange) {
      this.announce("Choose up to 6 adjacent seats in the same row to continue.");
      this.updateSelectionSummary();
      return;
    }

    this.flow.email = email;
    this.flow.showTimeline = true;
    this.flow.request = {
      method: "POST",
      path: "/api/v1/reservations",
      status: "pending",
      attempts: (this.flow.request?.attempts || 0) + 1,
      idempotencyKey: this.flow.request?.idempotencyKey || crypto.randomUUID(),
    };
    this.saveFlow();
    this.renderFlow();
    this.syncSeatMapState();
    this.clearHoldError();

    try {
      const reservation = await fetchJson("/api/v1/reservations", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Idempotency-Key": this.flow.request.idempotencyKey,
        },
        body: JSON.stringify({
          event_id: Number(this.element.dataset.eventId),
          quantity: this.selectedSeats.size,
          row_id: selectedRange.rowId,
          seat_start: selectedRange.seatStart,
          seat_end: selectedRange.seatEnd,
          email,
        }),
      });
      const firstSeat = Number(reservation.seat_start);
      const lastSeat = Number(reservation.seat_end);
      const row = this.event.rows.find(
        (item) => String(item.row_id) === String(reservation.row_id),
      );
      this.flow.reservation = {
        id: reservation.id,
        reference: `SW-${String(reservation.id)
          .replace(/[^a-z0-9]/gi, "")
          .slice(-6)
          .toUpperCase()}`,
        email,
        status: reservation.status,
        expiresAt: new Date(reservation.expires_at).getTime(),
        seats: Array.from({ length: lastSeat - firstSeat + 1 }, (_, index) => ({
          rowId: String(reservation.row_id),
          rowLabel: row?.label || reservation.row_id,
          number: firstSeat + index,
        })),
      };
      this.element.dataset.availabilityDeadline = String(this.flow.reservation.expiresAt);
      this.flow.request.status = "succeeded";
      this.flow.request.responseStatus = 201;
      this.flow.step = "payment";
      this.selectedSeats.clear();
      this.saveFlow();
      this.syncSeatMapState();
      this.renderFlow();
      this.startHoldClock();
      await this.loadCheckout();
    } catch (failure) {
      this.flow.request.status = "failed";
      if (failure.status === 409) {
        this.flow.request.idempotencyKey = null;
        this.selectionReady = false;
        this.reconciliationRequired = true;
        this.conflictRefreshPending = true;
        this.conflictRefreshRecoveryAllowed = false;
      }
      this.saveFlow();
      const error = this.element.querySelector("[data-hold-error]");
      error.textContent =
        failure.status === 409
          ? "Those seats were just taken. Choose available seats to continue."
          : failure.message || "We couldn’t hold those seats. Please try again.";
      error.hidden = false;
      if (failure.status === 409) this.requestAvailabilityRefresh();
      this.renderFlow();
      this.syncSeatMapState();
    } finally {
      this.updateHoldSubmitState();
    }
  }

  updateHoldSubmitState() {
    const button = this.element.querySelector("[data-hold-submit]");
    if (!button) return;
    button.disabled =
      !this.selectionReady ||
      !this.event ||
      this.availabilityBusy ||
      this.reconciliationRequired ||
      this.flow.request?.status === "pending" ||
      !this.selectedSeatRange() ||
      !this.element.querySelector("[name=email]")?.validity.valid;
  }

  async loadCheckout() {
    if (!this.flow.reservation || this.flow.reservation.status !== "held") return false;
    if (this.checkoutLoadPromise) return this.checkoutLoadPromise;

    const requestId = crypto.randomUUID();
    this.checkoutLoadPromise = new Promise((resolve) => {
      this.checkoutSetupWaiters.set(requestId, resolve);
      this.dispatchCheckout("checkout-setup", {
        requestId,
        reservation: this.flow.reservation,
        email: this.flow.reservation.email || this.flow.email,
        paymentSession: this.flow.paymentSession,
      });
    }).finally(() => {
      this.checkoutSetupWaiters.delete(requestId);
      this.checkoutLoadPromise = null;
    });
    return this.checkoutLoadPromise;
  }

  dispatchCheckout(name, detail = {}) {
    const panel = this.element.querySelector("#checkout-panel");
    panel?.dispatchEvent(new CustomEvent("portal--reservation:" + name, { bubbles: true, detail }));
  }

  resolveCheckoutSetupWaiters(value) {
    this.checkoutSetupWaiters.forEach((resolve) => resolve(value));
    this.checkoutSetupWaiters.clear();
    this.checkoutLoadPromise = null;
  }

  checkoutReady({ detail }) {
    if (detail.requestId && this.checkoutSetupWaiters.has(detail.requestId)) {
      this.checkoutSetupWaiters.get(detail.requestId)(true);
    }
    this.paymentConfiguration = detail.provider || { enabled: true };
    if (detail.paymentSession) this.flow.paymentSession = detail.paymentSession;
    this.saveFlow();
    this.renderFlow();
  }

  checkoutFailed({ detail }) {
    if (detail.requestId && this.checkoutSetupWaiters.has(detail.requestId)) {
      this.checkoutSetupWaiters.get(detail.requestId)(false);
    }
    if (detail.interrupted) {
      this.paymentConfiguration = null;
      return;
    }
    if (detail.kind === "element_load_error") {
      this.paymentConfiguration = { ...(this.paymentConfiguration || {}), enabled: false };
      this.renderFlow();
      return;
    }
    if (detail.requestId)
      this.paymentConfiguration = { ...(detail.provider || {}), enabled: false };
    if (detail.result?.status === "failed") {
      this.flow.payment = null;
      this.flow.step = "payment";
      this.saveFlow();
      this.renderFlow();
      this.loadCheckout();
    } else if (this.flow.step === "redirecting") {
      this.flow.payment = null;
      this.flow.step = "payment";
      this.saveFlow();
      this.renderFlow();
    }
  }

  checkoutRedirecting({ detail }) {
    this.flow.payment = detail.payment || { status: "processing", receivedAt: Date.now() };
    this.flow.step = "redirecting";
    this.saveFlow();
    this.renderFlow();
  }

  checkoutConfirmed({ detail }) {
    const reservation = this.flow.reservation;
    if (!reservation) return;
    reservation.status = detail.result?.reservation?.status || "confirmed";
    this.expiryPending = false;
    delete this.element.dataset.availabilityDeadline;
    this.flow.payment = { status: "succeeded", provider: "stripe", completedAt: Date.now() };
    this.flow.step = "confirmed";
    this.saveFlow();
    clearInterval(this.holdTimer);
    this.renderFlow();
    this.requestAvailabilityRefresh();
  }

  checkoutExpired() {
    if (this.flow.reservation) this.beginExpiryRefresh(this.flow.reservation.expiresAt);
  }

  restoreCheckoutReturn(sessionId) {
    const reservationId = new URLSearchParams(window.location.search).get("reservation_id");
    if (!this.flow.reservation || String(this.flow.reservation.id) !== String(reservationId)) {
      this.flow.step = "redirecting";
      this.renderFlow();
      this.dispatchCheckout("checkout-return", { sessionId, reservation: null });
      return;
    }

    this.flow.paymentSession ||= {};
    this.flow.paymentSession.session_id = sessionId;
    this.flow.payment = { status: "processing", returnedAt: Date.now() };
    this.flow.step = "redirecting";
    this.saveFlow();
    this.renderFlow();
    this.dispatchCheckout("checkout-return", {
      sessionId,
      reservation: this.flow.reservation,
      paymentSession: this.flow.paymentSession,
    });
  }

  pollCheckoutStatus(sessionId) {
    this.dispatchCheckout("checkout-poll", {
      sessionId,
      reservation: this.flow.reservation,
      paymentSession: this.flow.paymentSession,
    });
  }

  formatPaymentAmount(amount, currency) {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: currency.toUpperCase(),
    }).format(Number(amount) / 100);
  }

  renderFlow() {
    const panel = this.element.querySelector("#checkout-panel");
    const stages = this.element.querySelectorAll("[data-flow-stage]");
    const step = this.flow.step;
    this.updateAvailabilityCount();
    const seatLegend = this.element.querySelector("[data-seat-legend]");
    if (seatLegend) {
      seatLegend.textContent =
        this.flow.reservation?.status === "confirmed"
          ? "Your confirmed seats"
          : this.flow.reservation?.status === "held"
            ? "Your held seats"
            : "Your selection";
    }
    const stageVisible =
      step !== "seats" ||
      this.flow.showTimeline ||
      (this.flow.furthestStep || 1) > 1 ||
      this.selectedSeats.size > 0;
    panel.hidden = !stageVisible;
    panel.classList.toggle("hidden", !stageVisible);
    stages.forEach((stage) => {
      stage.hidden = stage.dataset.flowStage !== step;
    });

    const currentStep = STEP_NUMBERS[step] || STEP_NUMBERS.seats;
    const furthestStep = Math.max(this.flow.furthestStep || 1, currentStep);
    panel.querySelectorAll("[data-booking-step]").forEach((item, index) => {
      const isCurrent = index + 1 === currentStep;
      const isComplete = step === "confirmed" || index + 1 < furthestStep;
      item.classList.toggle("step-primary", isCurrent && step !== "confirmed");
      item.classList.toggle("step-success", isComplete);
      item.classList.toggle("before:bg-success", index > 0 && index < furthestStep);
      item.classList.toggle("font-semibold", isCurrent);
      item.dataset.content = isComplete ? "✓" : String(index + 1);
      if (isCurrent) item.setAttribute("aria-current", "step");
      else item.removeAttribute("aria-current");

      const control = item.querySelector("[data-flow-step]");
      if (control) {
        control.disabled = !this.canNavigateToStep(control.dataset.flowStep);
        if (isCurrent) control.setAttribute("aria-current", "step");
        else control.removeAttribute("aria-current");
      }
    });

    this.element.querySelectorAll("[data-seat-summary]").forEach((node) => {
      const seats = this.flow.reservation?.seats || this.selectedSeatDetails();
      node.textContent = this.formatSeatSummary(seats);
    });
    this.updateHoldDetails();

    const reservationRequestTracker = panel.querySelector("[data-reservation-request]");
    const reservationRequestStatus = panel.querySelector("[data-reservation-request-status]");
    const reservationRequestAttempt = panel.querySelector("[data-reservation-request-attempt]");
    if (reservationRequestTracker && reservationRequestStatus && reservationRequestAttempt) {
      const request = this.flow.request;
      const pending = request?.status === "pending";
      const confirmed = this.flow.reservation?.status === "confirmed";
      reservationRequestTracker.hidden = !request || !pending;
      reservationRequestStatus.textContent = pending
        ? "Placing hold"
        : confirmed
          ? "Confirmed"
          : "Hold active";
      reservationRequestStatus.className = [
        "badge",
        pending ? "badge-warning" : "badge-success",
        "badge-soft",
      ].join(" ");
      reservationRequestAttempt.textContent = pending
        ? "Securing your seats…"
        : confirmed
          ? "Your booking is confirmed. A confirmation has been sent to your email."
          : "Your seats are held while you complete checkout.";
    }

    const emailInput = panel.querySelector("[name=email]");
    const heldReservation = this.flow.reservation?.status === "held";
    if (emailInput) {
      if (this.flow.email) emailInput.value = this.flow.email;
      emailInput.readOnly = heldReservation;
    }
    const emailHelp = panel.querySelector("[data-email-help]");
    if (emailHelp) {
      emailHelp.textContent = heldReservation
        ? "This email is attached to your hold. Cancel the hold before changing it."
        : "We’ll send your tickets and booking details here.";
    }
    const holdSubmit = panel.querySelector("[data-hold-submit]");
    if (holdSubmit) holdSubmit.hidden = heldReservation;
    this.updateHoldSubmitState();
    const paymentButton = panel.querySelector("[data-payment-submit]");
    if (paymentButton) {
      paymentButton.disabled =
        this.paymentConfiguration?.enabled !== true ||
        panel.dataset.paymentReady !== "true" ||
        this.flow.payment?.status === "processing";
      paymentButton.textContent =
        this.flow.payment?.status === "processing" ? "Confirming payment…" : "Pay securely";
    }
    const paymentStatus = panel.querySelector("[data-payment-status]");
    if (paymentStatus && this.flow.payment?.status === "processing") {
      paymentStatus.textContent = "Waiting for payment confirmation. Your seats remain held.";
      paymentStatus.hidden = false;
    }
    const paymentTitle = panel.querySelector("[data-payment-title]");
    const paymentCopy = panel.querySelector("[data-payment-copy]");
    if (paymentTitle && paymentCopy && this.flow.payment?.status === "processing") {
      paymentTitle.textContent = "Waiting for payment confirmation";
      paymentCopy.textContent = "Your seats remain held until your payment is confirmed.";
    }
    const invoice = panel.querySelector("[data-confirmed-invoice]");
    const paymentSession = this.flow.paymentSession;
    const ticketCount = this.flow.reservation?.seats?.length || 0;
    const hasConfirmedInvoice =
      this.flow.payment?.status === "succeeded" &&
      paymentSession?.amount !== null &&
      paymentSession?.amount !== undefined &&
      Number.isFinite(Number(paymentSession.amount)) &&
      Boolean(paymentSession.currency) &&
      ticketCount > 0 &&
      Number.isInteger(Number(paymentSession.amount) / ticketCount);
    if (invoice) invoice.hidden = !hasConfirmedInvoice;
    if (hasConfirmedInvoice) {
      const lineTotal = this.formatPaymentAmount(paymentSession.amount, paymentSession.currency);
      const unitPrice = this.formatPaymentAmount(
        Number(paymentSession.amount) / ticketCount,
        paymentSession.currency,
      );
      const seatSummary = this.formatSeatSummary(this.flow.reservation?.seats || []);
      panel.querySelector("[data-invoice-seat-summary]").textContent = seatSummary;
      panel.querySelector("[data-invoice-ticket-summary]").textContent =
        `${ticketCount} ${ticketCount === 1 ? "ticket" : "tickets"} × ${unitPrice} each`;
      panel.querySelector("[data-invoice-line-total]").textContent = lineTotal;
    }
    const requestStatus = panel.querySelector("[data-request-status]");
    if (requestStatus) {
      const request = this.flow.request;
      requestStatus.textContent =
        request?.status === "pending"
          ? "Placing your five-minute hold…"
          : request?.status === "succeeded"
            ? this.flow.reservation?.status === "held"
              ? "Your seats are held for five minutes."
              : this.flow.reservation?.status === "confirmed"
                ? "Your booking is confirmed."
                : "Your reservation flow is ready to continue."
            : "Your seats are ready. Continue to payment to hold them for five minutes.";
    }
    this.updateSelectionSummary();
    this.dispatchCheckout("checkout-stage", {
      stage: step,
      reservation: this.flow.reservation,
      paymentSession: this.flow.paymentSession,
    });
  }

  updateAvailabilityCount() {
    if (!this.event) return;
    const activeReservation = ["held", "confirmed"].includes(this.flow.reservation?.status);
    const unavailableSeats = new Set(
      this.event.rows.flatMap((row) =>
        row.reserved_seats.map((number) => this.seatKey(row.row_id, number)),
      ),
    );
    if (activeReservation) {
      this.flow.reservation.seats.forEach((seat) =>
        unavailableSeats.add(this.seatKey(seat.rowId, seat.number)),
      );
    }
    const available = Math.max(0, this.event.seat_count - unavailableSeats.size);
    this.updateAvailabilityPresentation(available);
  }

  updateHoldDetails() {
    const reservation = this.flow.reservation;
    if (!reservation) return;
    reservation.reference ||= `SW-${String(reservation.id)
      .replace(/[^a-z0-9]/gi, "")
      .slice(-6)
      .toUpperCase()}`;
    const expires = new Date(reservation.expiresAt);
    const deadline = formatDate(expires, { hour: "numeric", minute: "2-digit" });
    this.element.querySelectorAll("[data-hold-deadline]").forEach((node) => {
      node.textContent = deadline;
    });
    this.element.querySelectorAll("[data-reservation-reference]").forEach((node) => {
      node.textContent = reservation.reference || "Pending";
    });
    this.element.querySelectorAll("[data-reservation-email]").forEach((node) => {
      node.textContent = reservation.email;
    });
    this.element.querySelectorAll("[data-reservation-status]").forEach((node) => {
      const labels = { held: "Held", confirmed: "Confirmed", expired: "Expired" };
      const variants = {
        held: "badge-warning",
        confirmed: "badge-success",
        expired: "badge-error",
      };
      node.textContent = labels[reservation.status] || reservation.status;
      node.className = [
        "badge",
        variants[reservation.status] || "badge-neutral",
        "badge-soft",
      ].join(" ");
    });
  }

  startHoldClock() {
    clearInterval(this.holdTimer);
    if (this.flow.reservation?.status !== "held") return;
    this.updateCountdown();
    this.holdTimer = setInterval(() => this.updateCountdown(), 1000);
  }

  updateCountdown() {
    const reservation = this.flow.reservation;
    if (!reservation || reservation.status !== "held") return;
    const remaining = reservation.expiresAt - Date.now();
    if (remaining <= 0) {
      this.beginExpiryRefresh(reservation.expiresAt);
      return;
    }

    const minutes = Math.floor(remaining / 60_000);
    const seconds = Math.floor((remaining % 60_000) / 1000);
    const value = `${minutes}:${String(seconds).padStart(2, "0")}`;
    this.element.querySelectorAll("[data-hold-countdown]").forEach((node) => {
      node.textContent = `${value} remaining`;
    });
  }

  beginExpiryRefresh(deadline) {
    if (this.expiryPending) return;
    this.expiryPending = true;
    this.reconciliationRequired = true;
    this.element.dataset.availabilityDeadline = String(deadline);
    this.setAvailabilityPending(true);
    clearInterval(this.holdTimer);
    this.requestAvailabilityRefresh({ deadline });
  }

  cancelHold() {
    if (!this.flow.reservation || this.flow.reservation.status !== "held") return;
    this.requestReleaseHoldConfirmation();
  }

  requestReleaseHoldConfirmation() {
    this.dispatch("confirmation", { detail: { action: "release-hold" } });
  }

  async handleAlertConfirmed({ detail }) {
    if (detail.action === "release-hold") await this.releaseHold();
  }

  async releaseHold() {
    if (!this.flow.reservation || this.flow.reservation.status !== "held") return;
    if (this.releasingHold) return;
    this.releasingHold = true;
    const button = this.element.querySelector(
      "[data-flow-stage='payment'] [data-action*='cancelHold']",
    );
    const error = this.element.querySelector("[data-cancel-error]");
    if (button) button.disabled = true;
    if (error) error.hidden = true;
    try {
      await fetchJson(`/api/v1/reservations/${encodeURIComponent(this.flow.reservation.id)}`, {
        method: "DELETE",
      });
    } catch (failure) {
      this.releasingHold = false;
      if (this.flow.step !== "payment") {
        this.flow.step = "payment";
        this.saveFlow();
        this.renderFlow();
      }
      if (error)
        error.textContent =
          failure.message || "We couldn’t cancel this hold. It will expire automatically.";
      if (error) error.hidden = false;
      if (button) button.disabled = false;
      return;
    }

    clearInterval(this.holdTimer);
    this.resolveCheckoutSetupWaiters(false);
    this.dispatchCheckout("checkout-reset");
    this.paymentConfiguration = null;
    this.flow.reservation = null;
    this.flow.request = null;
    this.flow.payment = null;
    this.flow.paymentSession = null;
    this.flow.step = "seats";
    this.flow.furthestStep = 1;
    this.flow.showTimeline = false;
    this.selectedSeats.clear();
    this.releasingHold = false;
    this.expiryPending = false;
    this.reconciliationRequired = true;
    delete this.element.dataset.availabilityDeadline;
    this.saveFlow();
    this.setAvailabilityPending(true);
    this.renderFlow();
    const refreshed = await this.requestAvailabilityRefresh();
    if (!refreshed) return;
    this.announce("Your hold was released. Choose seats again to change your booking.");
    const seatingTitle = this.element.querySelector("#seating-title");
    seatingTitle?.scrollIntoView({ behavior: "smooth", block: "start" });
    seatingTitle?.focus({ preventScroll: true });
  }

  async startAgain() {
    clearInterval(this.holdTimer);
    this.resolveCheckoutSetupWaiters(false);
    this.dispatchCheckout("checkout-reset");
    this.paymentConfiguration = null;
    try {
      sessionStorage.removeItem(this.storageKey);
    } catch (_error) {
      // The in-memory state is reset below regardless of storage availability.
    }
    this.flow = { step: "seats", selectedSeats: [], request: null, reservation: null };
    this.selectedSeats.clear();
    this.expiryPending = false;
    this.reconciliationRequired = true;
    delete this.element.dataset.availabilityDeadline;
    this.setAvailabilityPending(true);
    this.renderFlow();
    await this.requestAvailabilityRefresh();
  }
}
