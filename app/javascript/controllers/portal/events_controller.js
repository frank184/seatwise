import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.page = 1
    this.selectedSeats = new Set()
    if (this.element.hasAttribute("data-events-index")) this.loadEvents()
    else this.loadEvent()
  }

  async fetchJson(url) {
    const response = await fetch(url, { headers: { Accept: "application/json" } })
    if (!response.ok) throw new Error(`Request failed (${response.status})`)
    return response.json()
  }

  clone(selector) {
    return this.element.querySelector(selector).content.firstElementChild.cloneNode(true)
  }

  dateLabel(value, options) {
    return new Intl.DateTimeFormat(undefined, options).format(new Date(value))
  }

  async loadEvents() {
    const loading = this.element.querySelector("#events-loading")
    const list = this.element.querySelector("#events-list")
    const empty = this.element.querySelector("#events-empty")
    const error = this.element.querySelector("#events-error")
    const count = this.element.querySelector("#event-count")
    const pagination = this.element.querySelector("#events-pagination")
    loading.hidden = false
    loading.classList.remove("hidden")
    list.hidden = true
    empty.hidden = true
    error.hidden = true
    error.replaceChildren()

    const url = new URL("/api/v1/events", window.location.origin)
    const params = new URLSearchParams(window.location.search)
    for (const key of ["q", "when", "sort"]) {
      if (params.has(key)) url.searchParams.set(key, params.get(key))
    }
    if (!url.searchParams.has("when")) url.searchParams.set("when", "upcoming")
    url.searchParams.set("page", this.page)

    try {
      const { data: events, meta } = await this.fetchJson(url)
      list.replaceChildren(...events.map((event) => {
        const card = this.clone("#event-card-template")
        if (event.past) card.classList.add("opacity-75", "grayscale")
        card.querySelector("[data-event-link]").href = `/events/${encodeURIComponent(event.id)}`
        card.querySelector("[data-event-date]").textContent = this.dateLabel(event.starts_at, { weekday: "short", month: "short", day: "numeric" })
        card.querySelector("[data-event-time]").textContent = this.dateLabel(event.starts_at, { hour: "numeric", minute: "2-digit" })
        card.querySelector("[data-event-venue]").textContent = event.venue.name
        card.querySelector("[data-event-name]").textContent = event.name
        card.querySelector("[data-event-capacity]").textContent = `${event.seat_count} seats in this room`
        card.querySelector("[data-event-availability]").textContent = `${event.available_count} seats open`
        card.querySelector("[data-event-past]").hidden = !event.past
        return card
      }))
      count.textContent = `${meta.total_count} ${meta.total_count === 1 ? "event" : "events"}`
      count.hidden = false
      if (!events.length) empty.append(this.clone("#event-empty-template"))
      empty.hidden = events.length !== 0
      list.hidden = events.length === 0
      pagination.hidden = meta.total_pages < 2
      const previous = pagination.querySelector("[data-page-previous]")
      const next = pagination.querySelector("[data-page-next]")
      previous.disabled = !meta.previous_page
      next.disabled = !meta.next_page
      pagination.querySelectorAll("[data-page-number]").forEach((button) => button.remove())
      for (let page = 1; page <= meta.total_pages; page += 1) {
        const button = document.createElement("button")
        button.type = "button"
        button.className = `btn btn-sm join-item${page === meta.page ? " btn-primary btn-active" : ""}`
        button.dataset.pageNumber = page
        button.dataset.action = "click->portal--events#goToPage"
        button.textContent = page
        button.setAttribute("aria-label", `Page ${page}`)
        if (page === meta.page) button.setAttribute("aria-current", "page")
        next.before(button)
      }
    } catch (_error) {
      error.append(this.clone("#event-error-template"))
      error.hidden = false
    } finally {
      loading.hidden = true
      loading.classList.add("hidden")
    }
  }

  previousPage() {
    this.page -= 1
    this.loadEvents()
  }

  filtersChanged() {
    this.element.querySelector("#event-filters").requestSubmit()
  }

  nextPage() {
    this.page += 1
    this.loadEvents()
  }

  goToPage({ currentTarget }) {
    this.page = Number(currentTarget.dataset.pageNumber)
    this.loadEvents()
  }

  async loadEvent() {
    const loading = this.element.querySelector("#event-loading")
    const content = this.element.querySelector("#event-content")
    const error = this.element.querySelector("#event-error")
    loading.hidden = false
    loading.classList.remove("hidden")
    content.hidden = true
    error.hidden = true
    error.replaceChildren()

    try {
      const { data: event } = await this.fetchJson(`/api/v1/events/${encodeURIComponent(this.element.dataset.eventId)}`)
      content.querySelector("[data-detail-date]").textContent = this.dateLabel(event.starts_at, { weekday: "long", month: "long", day: "numeric" })
      content.querySelector("[data-detail-name]").textContent = event.name
      content.querySelector("[data-detail-venue]").textContent = event.venue.name
      content.querySelector("[data-detail-start]").textContent = this.dateLabel(event.starts_at, { hour: "numeric", minute: "2-digit" })
      content.querySelector("[data-detail-end]").textContent = this.dateLabel(event.ends_at, { hour: "numeric", minute: "2-digit" })
      content.querySelector("[data-detail-seats]").textContent = `${event.seat_count} seats`
      content.querySelector("[data-detail-open]").textContent = `${event.available_count} seats`
      this.selectedSeats.clear()
      content.querySelector("[data-detail-rows]").replaceChildren(...event.rows.sort((a, b) => a.allocation_order - b.allocation_order).map((row) => {
        const section = document.createElement("div")
        section.className = "grid grid-cols-[auto_1fr] items-center gap-4 rounded-box bg-base-200 p-4"
        const label = document.createElement("span")
        label.className = "badge badge-neutral"
        label.textContent = `Row ${row.label}`
        const seats = document.createElement("div")
        seats.className = "flex w-full flex-wrap justify-center gap-1.5"
        seats.setAttribute("aria-label", `Seats in row ${row.label}`)
        const reserved = new Set(row.reserved_seats)
        for (let number = 1; number <= row.seat_count; number += 1) {
          const seat = document.createElement("button")
          seat.type = "button"
          const taken = reserved.has(number)
          seat.className = taken
            ? "size-4 cursor-not-allowed rounded-t-full border-2 border-dashed border-base-content/40 bg-base-300"
            : "size-4 rounded-t-full border border-success bg-success/70 hover:border-primary hover:bg-primary/30 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          seat.dataset.seat = number
          seat.dataset.row = row.row_id
          seat.dataset.rowLabel = row.label
          seat.dataset.action = "click->portal--events#toggleSeat"
          seat.disabled = taken
          seat.setAttribute("aria-pressed", "false")
          seat.setAttribute("aria-label", `Row ${row.label}, seat ${number}, ${taken ? "held or reserved" : "open"}`)
          seat.title = `Seat ${number}${taken ? ", held or reserved" : ", open"}`
          seats.append(seat)
        }
        section.append(label, seats)
        return section
      }))
      this.element.querySelector("[data-selection-count]").textContent = "Choose up to 6 open seats."
      this.element.querySelector("[data-selection-message]").textContent = ""
      this.element.querySelector("[data-selection-review]").disabled = true
      content.hidden = false
      document.title = `${event.name} · Seatwise`
    } catch (failure) {
      error.append(this.clone(failure.message.includes("404") ? "#event-not-found-template" : "#event-error-template"))
      error.hidden = false
    } finally {
      loading.hidden = true
      loading.classList.add("hidden")
    }
  }

  toggleSeat({ currentTarget: seat }) {
    const key = `${seat.dataset.row}:${seat.dataset.seat}`
    const message = this.element.querySelector("[data-selection-message]")
    if (this.selectedSeats.has(key)) {
      this.selectedSeats.delete(key)
      seat.setAttribute("aria-pressed", "false")
      seat.setAttribute("aria-label", `Row ${seat.dataset.rowLabel}, seat ${seat.dataset.seat}, open`)
      seat.title = `Seat ${seat.dataset.seat}, open`
      seat.className = "size-4 rounded-t-full border border-success bg-success/70 hover:border-primary hover:bg-primary/30 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
    } else if (this.selectedSeats.size < 6) {
      this.selectedSeats.add(key)
      seat.setAttribute("aria-pressed", "true")
      seat.setAttribute("aria-label", `Row ${seat.dataset.rowLabel}, seat ${seat.dataset.seat}, selected`)
      seat.title = `Seat ${seat.dataset.seat}, selected`
      seat.className = "size-4 rounded-t-full border border-primary bg-primary text-primary-content ring-2 ring-primary/30"
    } else {
      message.textContent = "Up to 6 seats can be previewed at a time."
      return
    }

    message.textContent = ""
    this.element.querySelector("[data-selection-count]").textContent = `${this.selectedSeats.size || "Choose up to 6"} ${this.selectedSeats.size ? "of 6 seats selected" : "open seats."}`
    this.element.querySelector("[data-selection-review]").disabled = this.selectedSeats.size === 0
  }

  reviewSelection(event) {
    event.preventDefault()
    const count = this.selectedSeats.size
    this.element.querySelector("[data-selection-message]").textContent = `${count} seat${count === 1 ? "" : "s"} selected for preview. No reservation has been created.`
  }

  retry() {
    if (this.element.hasAttribute("data-events-index")) this.loadEvents()
    else this.loadEvent()
  }
}
