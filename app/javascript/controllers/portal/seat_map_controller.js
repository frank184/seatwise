import { Controller } from "@hotwired/stimulus";

const SEAT_STYLES = {
  open: "size-6 cursor-pointer touch-none select-none rounded-t-full border border-success bg-success/70 hover:border-primary hover:bg-primary/30 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
  selected:
    "flex size-6 cursor-pointer touch-none select-none items-center justify-center rounded-t-full border border-primary bg-primary text-[0.625rem] font-semibold tabular-nums text-primary-content ring-2 ring-primary/30",
  unavailable:
    "size-6 cursor-not-allowed rounded-t-full border-2 border-dashed border-base-content/40 bg-base-300",
  yours:
    "flex size-6 cursor-default items-center justify-center rounded-t-full border-2 border-primary bg-primary text-[0.625rem] font-semibold tabular-nums text-primary-content ring-2 ring-primary/40",
};

export default class extends Controller {
  static values = {
    event: Object,
    selectedSeats: Array,
    reservation: Object,
    busy: Boolean,
  };

  connect() {
    this.draggingSeats = false;
    this.ignoreNextPointerClick = false;
    this.selectedSeatsValue = this.selectedSeatsValue || [];
    this.reservationValue = this.reservationValue || {};
    this.hasRenderedState = false;
  }

  updateState({ event, selectedSeats, reservation, busy }) {
    const eventState = JSON.stringify(event || {});
    const reservationState = JSON.stringify(reservation || {});
    const nextSelectedSeats = selectedSeats || [];
    const selectedSeatsState = JSON.stringify(nextSelectedSeats);
    const selectionOnlyChange =
      this.hasRenderedState &&
      eventState === this.eventState &&
      reservationState === this.reservationState &&
      Boolean(busy) === this.busyState;
    this.deferRender = true;
    this.eventValue = event || {};
    this.selectedSeatsValue = nextSelectedSeats;
    this.reservationValue = reservation || {};
    this.busyValue = Boolean(busy);
    this.deferRender = false;
    if (selectionOnlyChange) {
      if (selectedSeatsState !== this.selectedSeatsState) this.updateSeatButtons();
    } else {
      this.render();
    }
    this.eventState = eventState;
    this.selectedSeatsState = selectedSeatsState;
    this.reservationState = reservationState;
    this.busyState = Boolean(busy);
    this.hasRenderedState = true;
  }

  render() {
    const rowsElement = this.element.querySelector("[data-detail-rows]") || this.element;
    const tableBody = rowsElement.querySelector("tbody");
    if (!tableBody) return;

    const event = this.eventValue;
    if (!Array.isArray(event?.rows)) return;
    rowsElement.toggleAttribute("aria-busy", this.busyValue);
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
    const reservation = this.reservationValue;
    const reservationSeat = reservation.seats?.find(
      (item) => String(item.rowId) === String(row.row_id) && item.number === number,
    );
    const yours = reservationSeat && ["held", "confirmed"].includes(reservation.status);
    const selected = !unavailable && !yours && this.selectedSeatsValue.includes(key);
    const state = yours ? "yours" : selected ? "selected" : unavailable ? "unavailable" : "open";

    seat.type = "button";
    seat.className = SEAT_STYLES[state];
    seat.dataset.seat = number;
    seat.dataset.row = row.row_id;
    seat.dataset.rowLabel = row.label;
    if (yours) seat.dataset.heldSeat = `${row.row_id}:${number}`;
    seat.dataset.action =
      "pointerdown->portal--seat-map#startDrag pointerenter->portal--seat-map#dragAcrossSeat click->portal--seat-map#toggleSeat";
    const reservationActive = this.isReservationActive();
    seat.disabled = this.busyValue || unavailable || Boolean(yours) || reservationActive;
    seat.setAttribute("aria-pressed", String(selected || Boolean(yours)));
    seat.setAttribute(
      "aria-label",
      this.seatLabel(row.label, number, { unavailable, selected, yours, reservation }),
    );
    if (selected || yours) seat.textContent = String(number);
    seat.title = this.seatLabel(row.label, number, { unavailable, selected, yours, reservation });
    return seat;
  }

  seatKey(rowId, number) {
    return `${rowId}:${number}`;
  }

  updateSeatButtons() {
    this.element.querySelectorAll("button[data-seat]").forEach((seat) => {
      const key = this.seatKeyFrom(seat);
      const unavailable = seat.getAttribute("aria-label").endsWith(", held or reserved");
      const yours = seat.hasAttribute("data-held-seat");
      const selected = !unavailable && !yours && this.selectedSeatsValue.includes(key);
      const state = yours ? "yours" : selected ? "selected" : unavailable ? "unavailable" : "open";
      const rowLabel = seat.dataset.rowLabel;
      const number = Number(seat.dataset.seat);
      const label = this.seatLabel(rowLabel, number, {
        unavailable,
        selected,
        yours,
        reservation: this.reservationValue,
      });

      seat.className = SEAT_STYLES[state];
      seat.disabled =
        this.busyValue || unavailable || Boolean(yours) || this.isReservationActive();
      seat.setAttribute("aria-pressed", String(selected || Boolean(yours)));
      seat.setAttribute("aria-label", label);
      seat.textContent = selected || yours ? String(number) : "";
      seat.title = label;
    });
  }

  isReservationActive() {
    return ["held", "confirmed"].includes(this.reservationValue.status);
  }

  seatLabel(rowLabel, number, { unavailable, selected, yours, reservation }) {
    const state = yours
      ? `your seat, ${reservation.status}`
      : selected
        ? "selected"
        : unavailable
          ? "held or reserved"
          : "open";
    return `Row ${rowLabel}, seat ${number}, ${state}`;
  }

  startDrag(event) {
    if (event.button !== 0 || this.busyValue || this.isReservationActive()) return;
    event.preventDefault();
    this.draggingSeats = true;
    this.dragSelectSeats = !this.selectedSeatsValue.includes(this.seatKeyFrom(event.currentTarget));
    this.ignoreNextPointerClick = true;
    this.setSeatSelected(event.currentTarget, this.dragSelectSeats);
  }

  dragAcrossSeat({ currentTarget }) {
    if (this.draggingSeats) this.setSeatSelected(currentTarget, this.dragSelectSeats);
  }

  endDrag() {
    this.draggingSeats = false;
  }

  toggleSeat(event) {
    if (this.busyValue || this.isReservationActive()) return;
    if (event.detail > 0 && this.ignoreNextPointerClick) {
      this.ignoreNextPointerClick = false;
      return;
    }
    const seat = event.currentTarget;
    this.setSeatSelected(seat, !this.selectedSeatsValue.includes(this.seatKeyFrom(seat)));
  }

  seatKeyFrom(seat) {
    return this.seatKey(seat.dataset.row, Number(seat.dataset.seat));
  }

  setSeatSelected(seat, selected) {
    if (seat.disabled) return;
    const key = this.seatKeyFrom(seat);
    const nextSeats = new Set(this.selectedSeatsValue);
    if (selected) nextSeats.add(key);
    else nextSeats.delete(key);
    if (nextSeats.size === this.selectedSeatsValue.length) return;
    this.dispatch("selection-changed", { detail: { selectedSeats: [...nextSeats] } });
  }
}
