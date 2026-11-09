import { Controller } from "@hotwired/stimulus";
import { cloneTemplate, fetchJson, formatDate } from "controllers/portal/view_helpers";

const HOLD_LENGTH_MS = 5 * 60 * 1000;
const DEMO_REQUEST_DELAY_MS = 650;
const PAYMENT_HANDOFF_DELAY_MS = 900;

const SEAT_STYLES = {
  open: "size-6 cursor-pointer touch-none select-none rounded-t-full border border-success bg-success/70 hover:border-primary hover:bg-primary/30 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
  selected: "size-6 cursor-pointer touch-none select-none rounded-t-full border border-primary bg-primary text-primary-content ring-2 ring-primary/30",
  unavailable: "size-6 cursor-not-allowed rounded-t-full border-2 border-dashed border-base-content/40 bg-base-300",
  yours: "size-6 cursor-default rounded-t-full border-2 border-primary bg-primary text-primary-content ring-2 ring-primary/40",
};

const STEP_NUMBERS = { seats: 1, email: 2, payment: 3, redirecting: 3, confirmed: 4, expired: 2 };

export default class extends Controller {
  connect() {
    this.selectedSeats = new Set();
    this.flow = this.readFlow();
    this.selectedSeats = new Set(this.flow.selectedSeats);
    this.draggingSeats = false;
    this.ignoreNextPointerClick = false;
    this.loadEvent();
  }

  disconnect() {
    clearInterval(this.holdTimer);
  }

  get storageKey() {
    return `seatwise:reservation:${this.element.dataset.eventId}`;
  }

  readFlow() {
    try {
      const stored = JSON.parse(sessionStorage.getItem(this.storageKey));
      if (stored && Array.isArray(stored.selectedSeats)) {
        return { step: "seats", request: null, reservation: null, ...stored };
      }
    } catch (_error) {
      // Storage can be disabled by the browser; the flow still works in memory.
    }
    return { step: "seats", selectedSeats: [], request: null, reservation: null };
  }

  saveFlow() {
    this.flow.selectedSeats = [...this.selectedSeats];
    try {
      sessionStorage.setItem(this.storageKey, JSON.stringify(this.flow));
    } catch (_error) {
      // Keep the current flow usable if the browser blocks session storage.
    }
  }

  async loadEvent() {
    const loading = this.element.querySelector("#event-loading");
    const content = this.element.querySelector("#event-content");
    const error = this.element.querySelector("#event-error");
    loading.hidden = false;
    loading.classList.remove("hidden");
    content.hidden = true;
    error.hidden = true;
    error.replaceChildren();

    try {
      const { data: event } = await fetchJson(
        `/api/v1/events/${encodeURIComponent(this.element.dataset.eventId)}`,
      );
      this.event = event;
      this.renderEventDetails(content, event);
      this.renderReservationEventDetails(event);
      this.renderSeatMap(content, event);
      this.renderFlow();
      this.updateSelectionSummary();
      this.startHoldClock();
      content.hidden = false;
      document.title = `${event.name} · Seatwise`;
    } catch (failure) {
      error.append(
        cloneTemplate(
          this.element,
          failure.message.includes("404") ? "#event-not-found-template" : "#event-error-template",
        ),
      );
      error.hidden = false;
    } finally {
      loading.hidden = true;
      loading.classList.add("hidden");
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
    content.querySelector("[data-detail-open]").textContent = `${event.available_count} seats`;
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

  renderSeatMap(content, event) {
    const tableBody = content.querySelector("[data-detail-rows] tbody");
    const rows = [...event.rows].sort((left, right) => left.allocation_order - right.allocation_order);
    tableBody.replaceChildren(...rows.map((row) => this.renderRow(row)));
  }

  renderRow(row) {
    const tableRow = document.createElement("tr");
    const label = document.createElement("span");
    label.className = "badge badge-neutral badge-sm px-3";
    label.textContent = `Row ${row.label}`;

    const rowHeader = document.createElement("th");
    rowHeader.scope = "row";
    rowHeader.className = "w-28 px-4 py-3";
    rowHeader.append(label);

    const seats = document.createElement("div");
    seats.className = "mx-auto flex w-max items-center justify-center gap-1.5";
    const seatCell = document.createElement("td");
    seatCell.className = "text-center";
    const reservedSeats = new Set(row.reserved_seats);

    for (let number = 1; number <= row.seat_count; number += 1) {
      seats.append(this.renderSeat(row, number, reservedSeats.has(number)));
    }

    seatCell.append(seats);
    tableRow.append(rowHeader, seatCell);
    return tableRow;
  }

  renderSeat(row, number, unavailable) {
    const seat = document.createElement("button");
    const key = this.seatKey(row.row_id, number);
    const reservationSeat = this.reservationSeat(row.row_id, number);
    const yours = reservationSeat && ["held", "confirmed"].includes(this.flow.reservation.status);
    const selected = !unavailable && !yours && this.selectedSeats.has(key);
    const state = yours ? "yours" : selected ? "selected" : unavailable ? "unavailable" : "open";

    seat.type = "button";
    seat.className = SEAT_STYLES[state];
    seat.dataset.seat = number;
    seat.dataset.row = row.row_id;
    seat.dataset.rowLabel = row.label;
    seat.dataset.action =
      "pointerdown->portal--reservation#startSeatDrag pointerenter->portal--reservation#dragAcrossSeat click->portal--reservation#toggleSeat";
    const reservationActive = ["held", "confirmed"].includes(this.flow.reservation?.status);
    seat.disabled = unavailable || Boolean(yours) || reservationActive;
    seat.setAttribute("aria-pressed", String(selected || Boolean(yours)));
    seat.setAttribute("aria-label", this.seatLabel(row.label, number, { unavailable, selected, yours }));
    seat.title = this.seatLabel(row.label, number, { unavailable, selected, yours });
    return seat;
  }

  seatKey(rowId, number) {
    return `${rowId}:${number}`;
  }

  reservationSeat(rowId, number) {
    return this.flow.reservation?.seats.find(
      (seat) => String(seat.rowId) === String(rowId) && seat.number === number,
    );
  }

  seatLabel(rowLabel, number, { unavailable, selected, yours }) {
    const state = yours
      ? `your seat, ${this.flow.reservation.status}`
      : selected
        ? "selected"
        : unavailable
          ? "held or reserved"
          : "open";
    return `Row ${rowLabel}, seat ${number}, ${state}`;
  }

  startSeatDrag(event) {
    if (event.button !== 0 || this.flow.reservation) return;
    event.preventDefault();
    this.draggingSeats = true;
    this.dragSelectSeats = !this.selectedSeats.has(this.seatKeyFrom(event.currentTarget));
    this.ignoreNextPointerClick = true;
    this.setSeatSelected(event.currentTarget, this.dragSelectSeats);
  }

  dragAcrossSeat({ currentTarget }) {
    if (this.draggingSeats) this.setSeatSelected(currentTarget, this.dragSelectSeats);
  }

  endSeatDrag() {
    this.draggingSeats = false;
  }

  toggleSeat(event) {
    if (this.flow.reservation) return;
    if (event.detail > 0 && this.ignoreNextPointerClick) {
      this.ignoreNextPointerClick = false;
      return;
    }
    const seat = event.currentTarget;
    this.setSeatSelected(seat, !this.selectedSeats.has(this.seatKeyFrom(seat)));
  }

  seatKeyFrom(seat) {
    return this.seatKey(seat.dataset.row, Number(seat.dataset.seat));
  }

  setSeatSelected(seat, selected) {
    const key = this.seatKeyFrom(seat);
    if (selected === this.selectedSeats.has(key)) return;
    if (selected && this.selectedSeats.size >= 6) {
      this.announce("You can select up to 6 seats.");
      return;
    }

    if (selected) this.selectedSeats.add(key);
    else this.selectedSeats.delete(key);
    this.saveFlow();
    const row = this.event.rows.find((item) => String(item.row_id) === String(seat.dataset.row));
    seat.replaceWith(this.renderSeat(row, Number(seat.dataset.seat), false));
    this.updateSelectionSummary();
  }

  updateSelectionSummary() {
    const count = this.selectedSeats.size;
    const countText = this.element.querySelector("[data-selection-count]");
    const reservation = this.flow.reservation;
    const held = reservation?.status === "held";
    const confirmed = reservation?.status === "confirmed";
    countText.textContent = held
      ? `${reservation.seats.length} ${reservation.seats.length === 1 ? "seat" : "seats"} held for five minutes`
      : confirmed
        ? `${reservation.seats.length} ${reservation.seats.length === 1 ? "seat" : "seats"} confirmed`
        : count
          ? `${count} of 6 seats selected`
          : "Click or drag across up to 6 open seats.";
    const reviewButton = this.element.querySelector("[data-selection-review]");
    const reservationStatus = this.element.querySelector("[data-selection-reservation-status]");
    const reservationComplete = held || confirmed;
    reviewButton.hidden = reservationComplete;
    reviewButton.disabled = count === 0 || Boolean(reservation);
    reservationStatus.hidden = !reservationComplete;
    reservationStatus.textContent = confirmed ? "Booking confirmed" : "Seats held";
    this.element.querySelector("[data-selection-message]").textContent = "";
    const summarySeats = reservationComplete ? reservation.seats : this.selectedSeatDetails();
    this.element.querySelectorAll("[data-seat-summary]").forEach((node) => {
      node.textContent = this.formatSeatSummary(summarySeats);
    });
  }

  saveEmail({ currentTarget }) {
    this.flow.email = currentTarget.value.trim();
    this.saveFlow();
  }

  selectedSeatDetails() {
    return [...this.selectedSeats].map((key) => {
      const [rowId, seatNumber] = key.split(":");
      const row = this.event.rows.find((item) => String(item.row_id) === rowId);
      return { rowId, rowLabel: row?.label || rowId, number: Number(seatNumber) };
    });
  }

  formatSeatSummary(seats) {
    if (!seats.length) return "No seats selected";
    const rows = [...new Set(seats.map((seat) => String(seat.rowId)))];
    return rows.map((rowId) => {
      const row = this.event.rows.find((item) => String(item.row_id) === rowId);
      const numbers = seats.filter((seat) => String(seat.rowId) === rowId)
        .map((seat) => seat.number).sort((left, right) => left - right);
      const ranges = [];
      for (const number of numbers) {
        const previous = ranges[ranges.length - 1];
        if (previous && number === previous.end + 1) previous.end = number;
        else ranges.push({ start: number, end: number });
      }
      const labels = ranges.map(({ start, end }) => start === end ? `${start}` : `${start}–${end}`);
      return `Row ${row?.label || rowId} · seats ${labels.join(", ")}`;
    }).join(" · ");
  }

  announce(message) {
    this.element.querySelector("[data-selection-message]").textContent = message;
  }

  reviewSelection(event) {
    event.preventDefault();
    if (!this.selectedSeats.size || this.flow.reservation) return;
    this.flow.step = "email";
    this.saveFlow();
    this.renderFlow();
    this.focusStage("email");
  }

  backToSeats() {
    this.flow.step = "seats";
    this.saveFlow();
    this.renderFlow();
    this.updateSelectionSummary();
    this.element.querySelector("[data-selection-title]").focus();
  }

  retry() {
    this.loadEvent();
  }

  async placeHold(event) {
    event.preventDefault();
    if (this.flow.request?.status === "pending") return;
    const form = event.currentTarget;
    const email = form.querySelector("[name=email]").value.trim();
    const button = form.querySelector("[data-hold-submit]");

    this.flow.email = email;
    this.flow.request = {
      method: "POST",
      path: "/api/v1/reservations",
      status: "pending",
      attempts: (this.flow.request?.attempts || 0) + 1,
    };
    this.saveFlow();
    this.renderFlow();
    button.disabled = true;

    await new Promise((resolve) => setTimeout(resolve, DEMO_REQUEST_DELAY_MS));
    const now = Date.now();
    this.flow.reservation = {
      id: `res_${crypto.randomUUID().replaceAll("-", "").slice(0, 10)}`,
      reference: `SW-${crypto.randomUUID().replaceAll("-", "").slice(0, 6).toUpperCase()}`,
      email,
      seats: this.selectedSeatDetails(),
      status: "held",
      expiresAt: now + HOLD_LENGTH_MS,
      createdAt: now,
    };
    this.flow.request.status = "succeeded";
    this.flow.request.responseStatus = 201;
    this.flow.step = "payment";
    this.saveFlow();
    this.renderSeatMap(this.element.querySelector("#event-content"), this.event);
    this.renderFlow();
    this.startHoldClock();
    this.focusStage("payment");
  }

  renderFlow() {
    const panel = this.element.querySelector("#checkout-panel");
    const stages = this.element.querySelectorAll("[data-flow-stage]");
    const step = this.flow.step;
    this.updateAvailabilityCount();
    const seatLegend = this.element.querySelector("[data-seat-legend]");
    if (seatLegend) {
      seatLegend.textContent = this.flow.reservation?.status === "confirmed"
        ? "Your confirmed seats"
        : this.flow.reservation?.status === "held"
          ? "Your held seats"
          : "Your selection";
    }
    const stageVisible = step !== "seats";
    panel.hidden = !stageVisible;
    panel.classList.toggle("hidden", !stageVisible);
    stages.forEach((stage) => {
      stage.hidden = stage.dataset.flowStage !== step;
    });

    const currentStep = STEP_NUMBERS[step] || STEP_NUMBERS.seats;
    panel.querySelectorAll("[data-booking-step]").forEach((item, index) => {
      const isCurrent = index + 1 === currentStep;
      const isComplete = step === "confirmed" || index + 1 < currentStep;
      item.classList.toggle("step-primary", isCurrent && step !== "confirmed");
      item.classList.toggle("step-success", isComplete);
      item.classList.toggle("font-semibold", isCurrent);
      item.dataset.content = isComplete ? "✓" : String(index + 1);
      if (isCurrent) item.setAttribute("aria-current", "step");
      else item.removeAttribute("aria-current");
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
      reservationRequestStatus.textContent = pending ? "Placing hold" : confirmed ? "Confirmed" : "Hold active";
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
    if (emailInput && this.flow.email) emailInput.value = this.flow.email;
    const payment = this.flow.payment || {};
    const paymentPending = payment.status === "redirecting";
    const providerLabels = { card: "Card payment", stripe: "Stripe Checkout", paypal: "PayPal" };
    panel.querySelectorAll("[data-payment-submit]").forEach((button) => {
      const provider = button.dataset.paymentProvider;
      button.disabled = paymentPending;
      const label = button.querySelector("[data-payment-label]");
      if (label) {
        label.textContent = paymentPending ? `Opening ${providerLabels[provider]}…` : "Pay with";
      } else {
        button.textContent = paymentPending
          ? provider === "card" ? "Processing card…" : `Opening ${providerLabels[provider]}…`
          : provider === "card" ? "Pay by card" : `Pay with ${provider === "paypal" ? "PayPal" : "Stripe"}`;
      }
    });
    const paymentBrand = panel.querySelector("[data-payment-brand]");
    if (paymentBrand) paymentBrand.textContent = providerLabels[payment.provider] || "Secure checkout";
    const paymentBadge = panel.querySelector("[data-payment-badge]");
    if (paymentBadge) paymentBadge.textContent = payment.provider === "card" ? "Card processing" : "Hosted checkout";
    const paymentTitle = panel.querySelector("[data-payment-title]");
    const paymentCopy = panel.querySelector("[data-payment-copy]");
    if (paymentTitle && paymentCopy) {
      const returning = this.flow.payment?.phase === "returning";
      const provider = payment.provider;
      paymentTitle.textContent = returning
        ? provider === "card" ? "Confirming your payment…" : "Returning to Seatwise…"
        : provider === "card" ? "Processing your card…" : `Opening ${providerLabels[provider]}…`;
      paymentCopy.textContent = returning
        ? "Payment complete. We’re bringing you back to your reservation."
        : provider === "card"
          ? "This demo is simulating a card payment. No payment is sent."
          : `Your seats are held while ${providerLabels[provider]} opens.`;
    }
    const paymentMethod = panel.querySelector("[data-payment-method]");
    if (paymentMethod) {
      paymentMethod.textContent = payment.provider === "card" && payment.last4
        ? `Card ending in ${payment.last4}`
        : providerLabels[payment.provider] || "Pending";
    }
    const requestStatus = panel.querySelector("[data-request-status]");
    if (requestStatus) {
      const request = this.flow.request;
      requestStatus.textContent = request?.status === "pending"
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
  }

  updateAvailabilityCount() {
    if (!this.event) return;
    const activeReservation = ["held", "confirmed"].includes(this.flow.reservation?.status);
    const heldSeatCount = activeReservation ? this.flow.reservation.seats.length : 0;
    const available = Math.max(0, this.event.available_count - heldSeatCount);
    const count = this.element.querySelector("[data-detail-open]");
    if (count) count.textContent = `${available} seats`;
  }

  updateHoldDetails() {
    const reservation = this.flow.reservation;
    if (!reservation) return;
    reservation.reference ||= `SW-${String(reservation.id).replace(/[^a-z0-9]/gi, "").slice(-6).toUpperCase()}`;
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
      const variants = { held: "badge-warning", confirmed: "badge-success", expired: "badge-error" };
      node.textContent = labels[reservation.status] || reservation.status;
      node.className = ["badge", variants[reservation.status] || "badge-neutral", "badge-soft"].join(" ");
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
      reservation.status = "expired";
      this.flow.step = "expired";
      this.selectedSeats.clear();
      this.saveFlow();
      clearInterval(this.holdTimer);
      this.renderSeatMap(this.element.querySelector("#event-content"), this.event);
      this.renderFlow();
      this.updateSelectionSummary();
      this.focusStage("expired");
      return;
    }

    const minutes = Math.floor(remaining / 60_000);
    const seconds = Math.floor((remaining % 60_000) / 1000);
    const value = `${minutes}:${String(seconds).padStart(2, "0")}`;
    this.element.querySelectorAll("[data-hold-countdown]").forEach((node) => {
      node.textContent = `${value} remaining`;
    });
  }

  cancelHold() {
    clearInterval(this.holdTimer);
    this.flow.reservation = null;
    this.flow.request = null;
    this.flow.payment = null;
    this.flow.step = "seats";
    this.selectedSeats.clear();
    this.saveFlow();
    this.renderSeatMap(this.element.querySelector("#event-content"), this.event);
    this.renderFlow();
    this.updateSelectionSummary();
    this.element.querySelector("[data-selection-title]").focus();
  }

  async completePayment(event) {
    event.preventDefault();
    const reservation = this.flow.reservation;
    if (!reservation || reservation.status !== "held" || this.flow.payment?.status === "redirecting") return;
    if (reservation.expiresAt <= Date.now()) {
      this.updateCountdown();
      return;
    }
    const provider = event.currentTarget.dataset.paymentProvider;
    const cardNumber = provider === "card"
      ? event.currentTarget.elements.card_number.value.replace(/\D/g, "").slice(-4)
      : null;
    this.flow.payment = {
      status: "redirecting",
      phase: "opening",
      startedAt: Date.now(),
      provider,
      ...(cardNumber && { last4: cardNumber }),
    };
    this.flow.step = "redirecting";
    this.saveFlow();
    this.renderFlow();
    this.focusStage("redirecting");
    await new Promise((resolve) => setTimeout(resolve, PAYMENT_HANDOFF_DELAY_MS));
    if (reservation.status !== "held" || reservation.expiresAt <= Date.now()) {
      this.updateCountdown();
      return;
    }
    this.flow.payment.phase = "returning";
    this.saveFlow();
    this.renderFlow();
    await new Promise((resolve) => setTimeout(resolve, DEMO_REQUEST_DELAY_MS));
    if (reservation.status !== "held" || reservation.expiresAt <= Date.now()) {
      this.updateCountdown();
      return;
    }
    reservation.status = "confirmed";
    this.flow.payment = { ...this.flow.payment, status: "succeeded", completedAt: Date.now() };
    this.flow.step = "confirmed";
    this.saveFlow();
    clearInterval(this.holdTimer);
    this.renderSeatMap(this.element.querySelector("#event-content"), this.event);
    this.renderFlow();
    this.focusStage("confirmed");
  }

  startAgain() {
    clearInterval(this.holdTimer);
    try {
      sessionStorage.removeItem(this.storageKey);
    } catch (_error) {
      // The in-memory state is reset below regardless of storage availability.
    }
    this.flow = { step: "seats", selectedSeats: [], request: null, reservation: null };
    this.selectedSeats.clear();
    this.renderSeatMap(this.element.querySelector("#event-content"), this.event);
    this.renderFlow();
    this.updateSelectionSummary();
    this.element.querySelector("[data-selection-title]").focus();
  }

  focusStage(name) {
    const panel = this.element.querySelector("#checkout-panel");
    const heading = this.element.querySelector(`[data-flow-stage="${name}"] [data-stage-heading]`);
    panel?.scrollIntoView({ block: "start", behavior: "smooth" });
    heading?.focus({ preventScroll: true });
  }
}
