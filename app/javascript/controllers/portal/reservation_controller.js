import { Controller } from "@hotwired/stimulus";
import { cloneTemplate, fetchJson, formatDate } from "controllers/portal/view_helpers";

const SEAT_STYLES = {
  open: "size-6 cursor-pointer touch-none select-none rounded-t-full border border-success bg-success/70 hover:border-primary hover:bg-primary/30 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
  selected:
    "flex size-6 cursor-pointer touch-none select-none items-center justify-center rounded-t-full border border-primary bg-primary text-[0.625rem] font-semibold tabular-nums text-primary-content ring-2 ring-primary/30",
  unavailable:
    "size-6 cursor-not-allowed rounded-t-full border-2 border-dashed border-base-content/40 bg-base-300",
  yours:
    "flex size-6 cursor-default items-center justify-center rounded-t-full border-2 border-primary bg-primary text-[0.625rem] font-semibold tabular-nums text-primary-content ring-2 ring-primary/40",
};

const STEP_NUMBERS = { seats: 1, email: 2, payment: 3, redirecting: 3, confirmed: 4, expired: 2 };

export default class extends Controller {
  connect() {
    this.selectedSeats = new Set();
    this.flow = this.readFlow();
    this.selectedSeats = new Set(this.flow.selectedSeats);
    this.draggingSeats = false;
    this.ignoreNextPointerClick = false;
    this.paymentConfiguration = null;
    this.stripe = null;
    this.checkout = null;
    this.checkoutActions = null;
    this.paymentElement = null;
    this.expressCheckoutElement = null;
    this.loadEvent();
  }

  disconnect() {
    clearInterval(this.holdTimer);
    this.paymentElement?.unmount?.();
    this.expressCheckoutElement?.unmount?.();
  }

  get storageKey() {
    return `seatwise:reservation:${this.element.dataset.eventId}`;
  }

  readFlow() {
    try {
      const stored = JSON.parse(sessionStorage.getItem(this.storageKey));
      if (stored && Array.isArray(stored.selectedSeats)) {
        const flow = { step: "seats", request: null, reservation: null, ...stored };
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
        { cache: "no-store" },
      );
      this.event = event;
      this.renderEventDetails(content, event);
      this.renderReservationEventDetails(event);
      this.renderSeatMap(content, event);
      this.renderFlow();
      this.updateSelectionSummary();
      this.startHoldClock();
      const checkoutSessionId = new URLSearchParams(window.location.search).get("session_id");
      if (checkoutSessionId) {
        this.restoreCheckoutReturn(checkoutSessionId);
      } else if (this.flow.step === "payment" && this.flow.reservation?.status === "held") {
        this.loadCheckout();
      } else if (this.flow.step === "redirecting" && this.flow.reservation?.status === "held") {
        const sessionId = this.flow.paymentSession?.session_id;
        if (sessionId) this.pollCheckoutStatus(sessionId);
      }
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

  async refreshEventAvailability() {
    try {
      const { data: event } = await fetchJson(
        `/api/v1/events/${encodeURIComponent(this.element.dataset.eventId)}`,
        { cache: "no-store" },
      );
      this.event = event;
      this.renderSeatMap(this.element.querySelector("#event-content"), event);
      this.renderEventDetails(this.element.querySelector("#event-content"), event);
      this.updateAvailabilityCount();
    } catch (_error) {
      // Keep the current seat map visible if refreshing availability fails.
    }
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
    const rows = [...event.rows].sort(
      (left, right) => left.allocation_order - right.allocation_order,
    );
    tableBody.replaceChildren(...rows.map((row) => this.renderRow(row)));
  }

  renderRow(row) {
    const tableRow = document.createElement("tr");
    const label = document.createElement("span");
    label.className = "badge badge-neutral badge-sm whitespace-nowrap px-3";
    label.textContent = `Row ${row.label}`;

    const rowHeader = document.createElement("th");
    rowHeader.scope = "row";
    rowHeader.className = "whitespace-nowrap px-4 py-3";
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
    if (yours) seat.dataset.heldSeat = `${row.row_id}:${number}`;
    seat.dataset.action =
      "pointerdown->portal--reservation#startSeatDrag pointerenter->portal--reservation#dragAcrossSeat click->portal--reservation#toggleSeat";
    const reservationActive = ["held", "confirmed"].includes(this.flow.reservation?.status);
    seat.disabled = unavailable || Boolean(yours) || reservationActive;
    seat.setAttribute("aria-pressed", String(selected || Boolean(yours)));
    seat.setAttribute(
      "aria-label",
      this.seatLabel(row.label, number, { unavailable, selected, yours }),
    );
    if (selected || yours) seat.textContent = String(number);
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
    if (this.flow.request?.status === "failed") this.flow.request.idempotencyKey = null;
    this.saveFlow();
    const row = this.event.rows.find((item) => String(item.row_id) === String(seat.dataset.row));
    seat.replaceWith(this.renderSeat(row, Number(seat.dataset.seat), false));
    this.updateSelectionSummary();
    this.renderFlow();
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
    const reviewButton = this.element.querySelector("[data-selection-review]");
    const reservationStatus = this.element.querySelector("[data-selection-reservation-status]");
    const reservationComplete = held || confirmed;
    reviewButton.textContent = this.flow.step === "email" ? "Edit seats" : "Review seats";
    reviewButton.hidden = reservationComplete;
    reviewButton.disabled = count === 0 || Boolean(reservation);
    reservationStatus.hidden = !reservationComplete;
    reservationStatus.textContent = confirmed ? "Booking confirmed" : "Seats held";
    this.element.querySelector("[data-selection-message]").textContent = "";
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

      numbers.sort((left, right) => left - right).forEach((number) => {
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

  reviewSelection(event) {
    event.preventDefault();
    if (this.flow.step === "email") {
      this.backToSeats();
      return;
    }
    if (!this.selectedSeats.size || this.flow.reservation) return;
    this.flow.step = "email";
    this.saveFlow();
    this.renderFlow();
  }

  backToSeats() {
    this.flow.step = "seats";
    this.saveFlow();
    this.renderFlow();
    this.updateSelectionSummary();
    const seatingTitle = this.element.querySelector("#seating-title");
    seatingTitle?.scrollIntoView({ behavior: "smooth", block: "start" });
    seatingTitle?.focus({ preventScroll: true });
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
    if (step === "payment" && this.flow.reservation?.status === "held" && !this.paymentConfiguration) {
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
      (targetStep <= furthestStep || (step === "email" && this.selectedSeats.size > 0)) &&
      (step !== "payment" || this.flow.reservation?.status === "held") &&
      !["confirmed", "expired", "redirecting"].includes(this.flow.step)
    );
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
    if (this.selectedSeats.size < 1 || this.selectedSeats.size > 6) return;

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
    button.disabled = true;
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
      this.flow.request.status = "succeeded";
      this.flow.request.responseStatus = 201;
      this.flow.step = "payment";
      this.selectedSeats.clear();
      this.saveFlow();
      this.renderSeatMap(this.element.querySelector("#event-content"), this.event);
      this.renderFlow();
      this.startHoldClock();
      await this.loadCheckout();
    } catch (failure) {
      this.flow.request.status = "failed";
      this.saveFlow();
      this.renderFlow();
      const error = this.element.querySelector("[data-hold-error]");
      error.textContent = failure.message || "We couldn’t hold those seats. Please try again.";
      error.hidden = false;
      if (failure.message?.includes("available")) await this.refreshEventAvailability();
    } finally {
      button.disabled = false;
    }
  }

  async loadCheckout() {
    const status = this.element.querySelector("[data-payment-status]");
    const loading = this.element.querySelector("[data-payment-loading]");
    const payButton = this.element.querySelector("[data-payment-submit]");
    const error = this.element.querySelector("[data-payment-error]");
    const retryButton = this.element.querySelector("[data-payment-retry]");
    if (!this.flow.reservation || this.flow.reservation.status !== "held") return;

    this.paymentElement?.unmount?.();
    this.expressCheckoutElement?.unmount?.();
    if (retryButton) retryButton.hidden = true;
    this.checkout = null;
    this.checkoutActions = null;
    status.textContent = "Loading payment options…";
    status.hidden = false;
    status.classList.remove("text-error");
    loading.hidden = false;
    payButton.disabled = true;
    error.hidden = true;

    try {
      const organizationResponse = await fetchJson("/api/v1/organizations/development");
      const provider = organizationResponse.data?.payment_provider;
      this.paymentConfiguration = provider;
      if (!provider?.enabled || provider.provider_key !== "stripe" || !provider.publishable_key) {
        throw new Error(
          "Online payment is temporarily unavailable. Your seats remain held while you try again.",
        );
      }
      if (
        this.flow.reservation.status !== "held" ||
        this.flow.reservation.expiresAt <= Date.now()
      ) {
        this.updateCountdown();
        return;
      }

      await this.waitForStripe();
      this.stripe = window.Stripe(provider.publishable_key);
      if (!this.stripe)
        throw new Error("Online payment is temporarily unavailable. Please try again shortly.");

      const sessionResponse = await fetchJson(
        `/api/v1/reservations/${encodeURIComponent(this.flow.reservation.id)}/checkout/session`,
        { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" },
      );
      const session = sessionResponse.data || sessionResponse;
      if (!session.client_secret)
        throw new Error("We couldn’t start secure checkout. Your seats remain held.");
      if (
        this.flow.reservation.status !== "held" ||
        this.flow.reservation.expiresAt <= Date.now()
      ) {
        this.updateCountdown();
        return;
      }
      this.flow.paymentSession = {
        session_id: session.session_id,
        amount: session.amount,
        currency: session.currency,
        status: session.status,
      };
      this.renderPaymentTotal(session.amount, session.currency);
      this.saveFlow();

      this.checkout = this.stripe.initCheckoutElementsSdk({
        clientSecret: session.client_secret,
        elementsOptions: {
          appearance: { theme: "stripe", inputs: "condensed", labels: "auto" },
        },
      });
      let actionsTimeout;
      const actionsResult = await Promise.race([
        this.checkout.loadActions(),
        new Promise((_, reject) => {
          actionsTimeout = window.setTimeout(
            () => reject(new Error("Secure payment is taking too long to load. Please try again.")),
            15_000,
          );
        }),
      ]).finally(() => window.clearTimeout(actionsTimeout));
      if (actionsResult.type !== "success") {
        throw new Error("Secure payment couldn’t be loaded. Your seats remain held.");
      }
      this.checkoutActions = actionsResult.actions;
      this.mountExpressCheckout();
      this.mountPaymentElement();
      this.paymentConfiguration = { ...provider, enabled: true };
      status.textContent = "Enter your payment details to finish booking.";
      payButton.disabled = false;
    } catch (failure) {
      this.paymentConfiguration = { ...this.paymentConfiguration, enabled: false };
      this.showPaymentError(
        failure.message || "Online payment is temporarily unavailable. Your seats remain held.",
      );
      status.textContent = "Payment setup didn’t finish. Your seats remain held.";
      if (retryButton) {
        retryButton.hidden = false;
        retryButton.disabled = false;
      }
      status.classList.add("text-error");
    } finally {
      loading.hidden = true;
    }
  }

  async waitForStripe() {
    if (window.Stripe) return;
    const script = document.querySelector('script[src^="https://js.stripe.com/"]');
    if (!script) throw new Error("Secure payment couldn’t be loaded. Please try again shortly.");
    await new Promise((resolve, reject) => {
      let timeout;
      const cleanup = () => {
        window.clearTimeout(timeout);
        script.removeEventListener("load", onLoad);
        script.removeEventListener("error", onError);
      };
      const onLoad = () => {
        cleanup();
        if (window.Stripe) resolve();
        else reject(new Error("Secure payment couldn’t be loaded. Please try again shortly."));
      };
      const onError = () => {
        cleanup();
        reject(new Error("Secure payment couldn’t be loaded. Please try again shortly."));
      };

      script.addEventListener("load", onLoad, { once: true });
      script.addEventListener("error", onError, { once: true });
      timeout = window.setTimeout(() => {
        cleanup();
        reject(new Error("Secure payment couldn’t be loaded. Please try again shortly."));
      }, 10_000);
      if (window.Stripe) {
        cleanup();
        resolve();
      }
    });
    if (!window.Stripe)
      throw new Error("Secure payment couldn’t be loaded. Please try again shortly.");
  }

  mountExpressCheckout() {
    const region = this.element.querySelector("[data-express-checkout-region]");
    const target = this.element.querySelector("[data-express-checkout-element]");
    const fallback = this.element.querySelector("[data-wallet-availability]");
    this.expressCheckoutElement = this.checkout.createExpressCheckoutElement({
      buttonType: { applePay: "buy", googlePay: "buy", paypal: "buynow" },
      paymentMethods: { googlePay: "always" },
    });
    this.expressCheckoutElement.on("ready", ({ availablePaymentMethods }) => {
      const available =
        availablePaymentMethods && Object.values(availablePaymentMethods).some(Boolean);
      region.hidden = !available;
      fallback.hidden = Boolean(available);
    });
    this.expressCheckoutElement.on("loaderror", () => this.handlePaymentElementLoadError());
    this.expressCheckoutElement.on("confirm", (event) => this.confirmPayment(event));
    this.expressCheckoutElement.mount(target);
  }

  mountPaymentElement() {
    const target = this.element.querySelector("[data-payment-element]");
    target.replaceChildren();
    this.paymentElement = this.checkout.createPaymentElement({
      layout: { type: "accordion", defaultCollapsed: true },
    });
    this.paymentElement.on("loaderror", () => this.handlePaymentElementLoadError());
    this.paymentElement.mount(target);
  }

  handlePaymentElementLoadError() {
    const payButton = this.element.querySelector("[data-payment-submit]");
    const retryButton = this.element.querySelector("[data-payment-retry]");
    const status = this.element.querySelector("[data-payment-status]");
    this.paymentConfiguration = { ...this.paymentConfiguration, enabled: false };
    if (payButton) payButton.disabled = true;
    if (retryButton) {
      retryButton.hidden = false;
      retryButton.disabled = false;
    }
    if (status) {
      status.textContent = "Secure payment couldn’t be loaded. Your seats remain held.";
      status.classList.add("text-error");
    }
    this.showPaymentError("Secure payment couldn’t be loaded. Please try again.");
  }

  renderPaymentTotal(amount, currency) {
    const total = this.element.querySelector("[data-reservation-total]");
    if (!total || !Number.isFinite(Number(amount)) || !currency) return;
    total.textContent = this.formatPaymentAmount(amount, currency);
  }

  formatPaymentAmount(amount, currency) {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: currency.toUpperCase(),
    }).format(Number(amount) / 100);
  }

  restoreCheckoutReturn(sessionId) {
    const reservationId = new URLSearchParams(window.location.search).get("reservation_id");
    if (!this.flow.reservation || String(this.flow.reservation.id) !== String(reservationId)) {
      this.flow.step = "redirecting";
      this.renderFlow();
      this.showCheckoutReturnStatus(
        "We couldn’t restore this reservation in your browser. Check your booking email for an update.",
      );
      return;
    }

    this.flow.paymentSession ||= {};
    this.flow.paymentSession.session_id = sessionId;
    this.flow.payment = { status: "processing", returnedAt: Date.now() };
    this.flow.step = "redirecting";
    this.saveFlow();
    this.renderFlow();
    this.pollCheckoutStatus(sessionId);
  }

  async checkPaymentStatus() {
    const sessionId =
      new URLSearchParams(window.location.search).get("session_id") ||
      this.flow.paymentSession?.session_id;
    if (sessionId) await this.pollCheckoutStatus(sessionId);
  }

  async pollCheckoutStatus(sessionId) {
    const reservation = this.flow.reservation;
    if (!reservation) return;
    const pollingId = Symbol("checkout-status-poll");
    this.checkoutPollingId = pollingId;
    // Hold expiry stops new payment attempts, but status lookup must continue:
    // a webhook may have confirmed the booking before the guest returned.
    const deadline = Date.now() + 120_000;
    const retryButton = this.element.querySelector("[data-check-payment-status]");
    retryButton.hidden = true;

    while (this.checkoutPollingId === pollingId && Date.now() < deadline) {
      try {
        const response = await fetchJson(
          `/api/v1/reservations/${encodeURIComponent(reservation.id)}/checkout?session_id=${encodeURIComponent(sessionId)}`,
        );
        const result = response.data || response;
        if (result.status === "succeeded") {
          reservation.status = result.reservation?.status || "confirmed";
          this.flow.payment = { status: "succeeded", provider: "stripe", completedAt: Date.now() };
          this.flow.step = "confirmed";
          this.saveFlow();
          clearInterval(this.holdTimer);
          await this.refreshEventAvailability();
          this.renderFlow();
          this.clearCheckoutReturnParams();
          return;
        }
        if (result.status === "failed") {
          this.flow.payment = null;
          this.flow.step = "payment";
          this.saveFlow();
          this.renderFlow();
          this.showPaymentError(
            "That payment didn’t go through. Your seats are still held; try another payment method.",
          );
          this.clearCheckoutReturnParams();
          await this.loadCheckout();
          return;
        }
        if (result.status === "expired") {
          reservation.status = "expired";
          this.flow.payment = null;
          this.flow.step = "expired";
          this.saveFlow();
          clearInterval(this.holdTimer);
          this.renderSeatMap(this.element.querySelector("#event-content"), this.event);
          this.renderFlow();
          await this.refreshEventAvailability();
          this.clearCheckoutReturnParams();
          return;
        }
        this.showCheckoutReturnStatus(
          "Your payment is processing. We’re waiting for Stripe to confirm it.",
        );
      } catch (_failure) {
        this.showCheckoutReturnStatus(
          "We’re having trouble checking the payment status. We’ll keep trying.",
        );
      }
      await new Promise((resolve) => setTimeout(resolve, 1500));
    }

    if (this.checkoutPollingId === pollingId) {
      if (reservation.expiresAt <= Date.now()) {
        this.updateCountdown();
      } else {
        this.showCheckoutReturnStatus(
          "Your payment is still being confirmed. You can check again in a moment.",
          true,
        );
      }
    }
  }

  showCheckoutReturnStatus(message, retry = false) {
    const status = this.element.querySelector("[data-checkout-return-status]");
    const button = this.element.querySelector("[data-check-payment-status]");
    status.textContent = message;
    button.hidden = !retry;
  }

  clearCheckoutReturnParams() {
    const url = new URL(window.location.href);
    url.searchParams.delete("session_id");
    url.searchParams.delete("reservation_id");
    window.history.replaceState({}, "", url);
  }

  showPaymentError(message) {
    const error = this.element.querySelector("[data-payment-error]");
    this.element.querySelector("[data-payment-status]").hidden = true;
    error.textContent = message;
    error.hidden = false;
  }

  async completePayment(event) {
    event.preventDefault();
    return this.confirmPayment();
  }

  async retryCheckout(event) {
    event.currentTarget.disabled = true;
    await this.loadCheckout();
  }

  async confirmPayment(expressEvent = null) {
    const reservation = this.flow.reservation;
    if (!reservation || reservation.status !== "held" || !this.checkoutActions) return;
    if (reservation.expiresAt <= Date.now()) {
      this.updateCountdown();
      return;
    }

    const error = this.element.querySelector("[data-payment-error]");
    error.hidden = true;
    try {
      this.flow.payment = { status: "processing", startedAt: Date.now() };
      this.saveFlow();
      this.renderFlow();
      const confirmOptions = { redirect: "if_required" };
      if (expressEvent) confirmOptions.expressCheckoutConfirmEvent = expressEvent;
      const result = await this.checkoutActions.confirm(confirmOptions);
      if (result.type === "error") {
        this.flow.payment = null;
        this.flow.step = "payment";
        this.saveFlow();
        this.renderFlow();
        this.showPaymentError(
          result.error?.message || "Your payment couldn’t be completed. Try another payment method.",
        );
        return;
      }

      // Payment confirmation is authoritative only after the server reconciles the Stripe event.
      this.flow.step = "redirecting";
      this.flow.payment = { status: "processing", receivedAt: Date.now() };
      this.saveFlow();
      this.renderFlow();
      if (this.flow.paymentSession?.session_id) {
        this.pollCheckoutStatus(this.flow.paymentSession.session_id);
      }
    } catch (failure) {
      console.error("Stripe checkout confirmation threw an error", {
        name: failure?.name,
        message: failure?.message,
      });
      this.flow.payment = null;
      this.flow.step = "payment";
      this.saveFlow();
      this.renderFlow();
      this.showPaymentError(
        "We couldn’t confirm that payment. Your hold is still active; please try again.",
      );
    }
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
    const paymentButton = panel.querySelector("[data-payment-submit]");
    if (paymentButton) {
      paymentButton.disabled =
        this.paymentConfiguration?.enabled !== true || this.flow.payment?.status === "processing";
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
      paymentCopy.textContent =
        "Your payment was submitted securely. We’ll confirm your booking as soon as Stripe verifies it.";
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
      reservation.status = "expired";
      this.flow.step = "expired";
      this.selectedSeats.clear();
      this.saveFlow();
      clearInterval(this.holdTimer);
      this.renderSeatMap(this.element.querySelector("#event-content"), this.event);
      this.renderFlow();
      this.updateSelectionSummary();
      this.refreshEventAvailability();
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
      if (error) error.textContent =
        failure.message || "We couldn’t cancel this hold. It will expire automatically.";
      if (error) error.hidden = false;
      if (button) button.disabled = false;
      return;
    }

    clearInterval(this.holdTimer);
    this.paymentElement?.unmount?.();
    this.expressCheckoutElement?.unmount?.();
    this.paymentConfiguration = null;
    this.checkout = null;
    this.checkoutActions = null;
    this.stripe = null;
    this.flow.reservation = null;
    this.flow.request = null;
    this.flow.payment = null;
    this.flow.paymentSession = null;
    this.flow.step = "seats";
    this.flow.furthestStep = 1;
    this.flow.showTimeline = true;
    this.selectedSeats.clear();
    this.releasingHold = false;
    this.saveFlow();
    await this.refreshEventAvailability();
    this.renderFlow();
    this.updateSelectionSummary();
    this.announce("Your hold was released. Choose seats again to change your booking.");
    const seatingTitle = this.element.querySelector("#seating-title");
    seatingTitle?.scrollIntoView({ behavior: "smooth", block: "start" });
    seatingTitle?.focus({ preventScroll: true });
  }

  async startAgain() {
    clearInterval(this.holdTimer);
    this.paymentElement?.unmount?.();
    this.expressCheckoutElement?.unmount?.();
    this.paymentConfiguration = null;
    this.stripe = null;
    this.checkout = null;
    this.checkoutActions = null;
    try {
      sessionStorage.removeItem(this.storageKey);
    } catch (_error) {
      // The in-memory state is reset below regardless of storage availability.
    }
    this.flow = { step: "seats", selectedSeats: [], request: null, reservation: null };
    this.selectedSeats.clear();
    await this.refreshEventAvailability();
    this.renderFlow();
    this.updateSelectionSummary();
  }
}
