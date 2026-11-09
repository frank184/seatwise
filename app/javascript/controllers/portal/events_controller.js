import { Controller } from "@hotwired/stimulus";
import { cloneTemplate, fetchJson, formatDate } from "controllers/portal/view_helpers";

export default class extends Controller {
  connect() {
    this.page = 1;
    this.loadEvents();
  }

  async loadEvents() {
    const loading = this.element.querySelector("#events-loading");
    const list = this.element.querySelector("#events-list");
    const empty = this.element.querySelector("#events-empty");
    const error = this.element.querySelector("#events-error");
    const count = this.element.querySelector("#event-count");
    const pagination = this.element.querySelector("#events-pagination");
    loading.hidden = false;
    loading.classList.remove("hidden");
    list.hidden = true;
    empty.hidden = true;
    error.hidden = true;
    error.replaceChildren();

    const url = new URL("/api/v1/events", window.location.origin);
    const params = new URLSearchParams(window.location.search);
    for (const key of ["q", "when", "sort"]) {
      if (params.has(key)) url.searchParams.set(key, params.get(key));
    }
    if (!url.searchParams.has("when")) url.searchParams.set("when", "upcoming");
    url.searchParams.set("page", this.page);

    try {
      const { data: events, meta } = await fetchJson(url);
      list.replaceChildren(...events.map((event) => this.renderEvent(event)));
      count.textContent = `${meta.total_count} ${meta.total_count === 1 ? "event" : "events"}`;
      count.hidden = false;
      if (!events.length) empty.append(cloneTemplate(this.element, "#event-empty-template"));
      empty.hidden = events.length !== 0;
      list.hidden = events.length === 0;
      this.renderPagination(pagination, meta);
    } catch (_error) {
      error.append(cloneTemplate(this.element, "#event-error-template"));
      error.hidden = false;
    } finally {
      loading.hidden = true;
      loading.classList.add("hidden");
    }
  }

  renderEvent(event) {
    const card = cloneTemplate(this.element, "#event-card-template");
    if (event.past) card.classList.add("opacity-75", "grayscale");
    card.querySelector("[data-event-link]").href = `/events/${encodeURIComponent(event.id)}`;
    card.querySelector("[data-event-date]").textContent = formatDate(event.starts_at, {
      weekday: "short",
      month: "short",
      day: "numeric",
    });
    card.querySelector("[data-event-time]").textContent = formatDate(event.starts_at, {
      hour: "numeric",
      minute: "2-digit",
    });
    card.querySelector("[data-event-venue]").textContent = event.venue.name;
    card.querySelector("[data-event-name]").textContent = event.name;
    card.querySelector("[data-event-capacity]").textContent = `${event.seat_count} seats in this room`;
    card.querySelector("[data-event-availability]").textContent = `${event.available_count} seats open`;
    card.querySelector("[data-event-past]").hidden = !event.past;
    return card;
  }

  renderPagination(pagination, meta) {
    pagination.hidden = meta.total_pages < 2;
    const previous = pagination.querySelector("[data-page-previous]");
    const next = pagination.querySelector("[data-page-next]");
    previous.disabled = !meta.previous_page;
    next.disabled = !meta.next_page;
    pagination.querySelectorAll("[data-page-number]").forEach((button) => button.remove());

    for (let page = 1; page <= meta.total_pages; page += 1) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `btn btn-sm join-item${page === meta.page ? " btn-primary btn-active" : ""}`;
      button.dataset.pageNumber = page;
      button.dataset.action = "click->portal--events#goToPage";
      button.textContent = page;
      button.setAttribute("aria-label", `Page ${page}`);
      if (page === meta.page) button.setAttribute("aria-current", "page");
      next.before(button);
    }
  }

  previousPage() {
    this.page -= 1;
    this.loadEvents();
  }

  filtersChanged() {
    this.element.querySelector("#event-filters").requestSubmit();
  }

  nextPage() {
    this.page += 1;
    this.loadEvents();
  }

  goToPage({ currentTarget }) {
    this.page = Number(currentTarget.dataset.pageNumber);
    this.loadEvents();
  }

  retry() {
    this.loadEvents();
  }
}
