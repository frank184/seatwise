import { Controller } from "@hotwired/stimulus";
import { cloneTemplate, fetchJson, formatDate } from "controllers/portal/view_helpers";

export default class extends Controller {
  connect() {
    this.page = Number(new URLSearchParams(window.location.search).get("page")) || 1;
    this.handlePopState = () => {
      this.page = Number(new URLSearchParams(window.location.search).get("page")) || 1;
      this.syncFiltersFromUrl();
      this.loadEvents();
    };
    window.addEventListener("popstate", this.handlePopState);
    this.syncFiltersFromUrl();
    this.updateFilterPresentation();
    this.loadEvents();
  }

  disconnect() {
    window.removeEventListener("popstate", this.handlePopState);
    this.abortController?.abort();
  }

  async loadEvents() {
    const loading = this.element.querySelector("#events-loading");
    const list = this.element.querySelector("#events-list");
    const empty = this.element.querySelector("#events-empty");
    const error = this.element.querySelector("#events-error");
    const count = this.element.querySelector("#event-count");
    const pagination = this.element.querySelector("#events-pagination");
    this.abortController?.abort();
    this.abortController = new AbortController();
    const { signal } = this.abortController;
    const initialLoad = !this.hasLoaded;
    if (initialLoad) {
      loading.hidden = false;
      loading.classList.remove("hidden");
      list.hidden = true;
    } else {
      list.setAttribute("aria-busy", "true");
    }
    empty.hidden = true;
    error.hidden = true;
    error.replaceChildren();

    const url = new URL("/api/v1/events", window.location.origin);
    const params = new URLSearchParams(window.location.search);
    for (const [key, value] of params.entries()) {
      if (key === "q" || key.startsWith("q[") || key === "when" || key === "sort" || key === "page") {
        url.searchParams.set(key, value);
      }
    }
    if (!url.searchParams.has("when")) url.searchParams.set("when", "upcoming");
    url.searchParams.set("page", this.page);

    try {
      const { data: events, meta } = await fetchJson(url, { signal });
      if (signal.aborted) return;
      list.replaceChildren(...events.map((event) => this.renderEvent(event)));
      count.textContent = `${meta.total_count} ${meta.total_count === 1 ? "event" : "events"}`;
      if (!events.length) empty.append(cloneTemplate(this.element, "#event-empty-template"));
      empty.hidden = events.length !== 0;
      list.hidden = events.length === 0;
      this.renderPagination(pagination, meta);
      this.hasLoaded = true;
    } catch (requestError) {
      if (requestError.name === "AbortError") return;
      error.append(cloneTemplate(this.element, "#event-error-template"));
      error.hidden = false;
    } finally {
      if (!signal.aborted) {
        loading.hidden = true;
        loading.classList.add("hidden");
        list.removeAttribute("aria-busy");
      }
    }
  }

  renderEvent(event) {
    const card = cloneTemplate(this.element, "#event-card-template");
    card.dataset.eventId = event.id;
    card.dataset.controller = "portal--availability";
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
    card.querySelector("[data-event-capacity]").textContent =
      `${event.seat_count} seats in this room`;
    this.updateAvailabilityPresentation(card, event);
    card.querySelector("[data-event-past]").hidden = !event.past;
    return card;
  }

  updateAvailabilityPresentation(card, event) {
    const available = Math.max(0, Number(event.available_count) || 0);
    const badge = card.querySelector("[data-event-availability-badge]");
    const label = card.querySelector("[data-event-availability]");
    const neutralClasses = ["border", "border-base-content/25", "bg-base-100", "text-base-content"];

    label.textContent =
      available === 0 ? "Sold out" : `${available} ${available === 1 ? "seat" : "seats"} open`;
    badge.classList.remove(...neutralClasses, "badge-soft", "badge-success");
    if (available === 0) {
      badge.classList.add(...neutralClasses);
    } else {
      badge.classList.add("badge-soft", "badge-success");
    }
  }

  availabilityUpdated({ detail: { event } }) {
    const card = [...this.element.querySelectorAll("#events-list article")].find(
      (item) => item.dataset.eventId === String(event.id),
    );
    if (card) this.updateAvailabilityPresentation(card, event);
  }

  renderPagination(pagination, meta) {
    pagination.hidden = meta.total_pages < 2;
    const previous = pagination.querySelector("[data-page-previous]");
    const next = pagination.querySelector("[data-page-next]");
    previous.disabled = !meta.previous_page;
    next.disabled = !meta.next_page;
    pagination.querySelectorAll("[data-page-number]").forEach((button) => button.remove());

    for (let page = 1; page <= meta.total_pages; page += 1) {
      const button = cloneTemplate(this.element, "#event-page-number-template");
      button.dataset.pageNumber = page;
      button.textContent = page;
      button.setAttribute("aria-label", `Page ${page}`);
      button.classList.toggle("btn-primary", page === meta.page);
      button.classList.toggle("btn-active", page === meta.page);
      if (page === meta.page) button.setAttribute("aria-current", "page");
      next.before(button);
    }
  }

  previousPage() {
    this.navigateToPage(this.page - 1);
  }

  submitFilters(event) {
    event.preventDefault();
    this.applyFilters();
  }

  filtersChanged() {
    this.applyFilters();
  }

  selectWhen({ currentTarget }) {
    this.element.querySelector("#event-date-filter").value = currentTarget.dataset.when;
    this.applyFilters();
  }

  selectSort({ currentTarget }) {
    const sort = this.element.querySelector("#event-sort-filter");
    const sortKey = currentTarget.dataset.sortKey;
    const descendingSort = { date: "latest", name: "name_desc" }[sortKey];
    const ascendingSort = { date: "soonest", name: "name" }[sortKey];
    const currentKey = sort.value.startsWith("name") ? "name" : "date";
    if (currentKey !== sortKey) {
      sort.value = ascendingSort;
    } else {
      sort.value = sort.value === descendingSort ? ascendingSort : descendingSort;
    }
    this.applyFilters();
  }

  nextPage() {
    this.navigateToPage(this.page + 1);
  }

  goToPage({ currentTarget }) {
    this.navigateToPage(Number(currentTarget.dataset.pageNumber));
  }

  navigateToPage(page) {
    this.page = page;
    const params = new URLSearchParams(window.location.search);
    if (this.page > 1) params.set("page", this.page);
    else params.delete("page");
    this.pushUrl(params);
    this.loadEvents();
  }

  retry() {
    this.loadEvents();
  }

  applyFilters() {
    const form = this.element.querySelector("#event-filters");
    const params = new URLSearchParams(new FormData(form));
    for (const key of [...params.keys()]) {
      if (params.get(key) === "" && key !== "when" && key !== "sort") params.delete(key);
    }
    this.page = 1;
    params.delete("page");
    this.pushUrl(params);
    this.updateFilterPresentation();
    this.loadEvents();
  }

  pushUrl(params) {
    const query = params.toString();
    window.history.pushState({}, "", `${window.location.pathname}${query ? `?${query}` : ""}`);
  }

  syncFiltersFromUrl() {
    const params = new URLSearchParams(window.location.search);
    const form = this.element.querySelector("#event-filters");
    form.querySelector('[name="q[name_or_venue_name_cont]"]').value =
      params.get("q[name_or_venue_name_cont]") || params.get("q") || "";
    form.querySelector('[name="q[venue_id_eq]"]').value = params.get("q[venue_id_eq]") || "";
    form.querySelector("#event-date-filter").value = params.get("when") || "upcoming";
    form.querySelector("#event-sort-filter").value = params.get("sort") || "soonest";
  }

  updateFilterPresentation() {
    const form = this.element.querySelector("#event-filters");
    const selectedWhen = form.querySelector("#event-date-filter").value;
    form.querySelectorAll("[data-when]").forEach((button) => {
      const selected = button.dataset.when === selectedWhen;
      button.classList.toggle("btn-primary", selected);
      button.setAttribute("aria-pressed", selected);
    });

    const sort = form.querySelector("#event-sort-filter").value;
    const sortKey = sort.startsWith("name") ? "name" : "date";
    const descending = sort === "latest" || sort === "name_desc";
    form.querySelectorAll("[data-sort-key]").forEach((button) => {
      const selected = button.dataset.sortKey === sortKey;
      button.classList.toggle("btn-primary", selected);
      button.setAttribute("aria-pressed", selected);
      form.querySelector(`[data-sort-indicator="${button.dataset.sortKey}"]`).classList.toggle("invisible", !selected);
      button.querySelector('[data-sort-direction="ascending"]').hidden = descending;
      button.querySelector('[data-sort-direction="descending"]').hidden = !descending;
      if (button.dataset.sortKey === "date") {
        button.setAttribute("aria-label", selected ? (descending ? "Date, latest first" : "Date, soonest first") : "Sort by date, soonest first");
        button.title = descending && selected ? "Date: latest first" : "Date: soonest first";
      } else {
        button.setAttribute("aria-label", selected ? (descending ? "Name, Z to A" : "Name, A to Z") : "Sort by name, A to Z");
        button.title = descending && selected ? "Name: Z to A" : "Name: A to Z";
      }
    });
  }
}
