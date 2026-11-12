import { Controller } from "@hotwired/stimulus";
import consumer from "channels/consumer";
import { fetchJson } from "controllers/portal/view_helpers";

const INITIAL_SUBSCRIPTION_TIMEOUT_MS = 2_000;

export default class extends Controller {
  connect() {
    this.eventId = this.element.dataset.eventId;
    this.subscriptionConnected = false;
    this.inFlight = null;
    this.refreshRequested = false;
    const persistedDeadline = Number(this.element.dataset.availabilityDeadline);
    this.expiryDeadline =
      Number.isFinite(persistedDeadline) && persistedDeadline > 0 ? persistedDeadline : null;
    this.refreshRequestIds = new Set();
    this.activeRequestIds = new Set();
    this.initialFallbackStarted = false;
    this.initialFallbackTimer = window.setTimeout(
      () => this.startInitialFallback(),
      INITIAL_SUBSCRIPTION_TIMEOUT_MS,
    );
    this.visibilityHandler = () => {
      if (this.subscriptionConnected && document.visibilityState === "visible") this.refresh();
    };
    document.addEventListener("visibilitychange", this.visibilityHandler);

    const callbacks = {
      connected: () => {
        this.subscriptionConnected = true;
        window.clearTimeout(this.initialFallbackTimer);
        this.initialFallbackTimer = null;
        this.refresh();
      },
      disconnected: () => {
        this.subscriptionConnected = false;
      },
      received: (message) => {
        if (message?.type === "availability_changed") this.refresh();
      },
    };
    const testFactory = window.__seatwiseAvailabilitySubscriptionFactory;
    this.subscription = testFactory
      ? testFactory(this.eventId, callbacks)
      : consumer.subscriptions.create(
          { channel: "EventAvailabilityChannel", event_id: this.eventId },
          callbacks,
        );
  }

  disconnect() {
    window.clearTimeout(this.initialFallbackTimer);
    document.removeEventListener("visibilitychange", this.visibilityHandler);
    this.subscription?.unsubscribe?.();
  }

  startInitialFallback() {
    window.clearTimeout(this.initialFallbackTimer);
    this.initialFallbackTimer = null;
    if (this.subscriptionConnected || this.initialFallbackStarted) return;
    this.initialFallbackStarted = true;
    this.refresh();
  }

  refresh({ detail } = {}) {
    const requestId = detail?.requestId;
    if (requestId) this.refreshRequestIds.add(requestId);
    if (Object.hasOwn(detail || {}, "deadline")) {
      this.expiryDeadline = Number.isFinite(detail.deadline) ? detail.deadline : null;
    } else {
      const deadline = Number(this.element.dataset.availabilityDeadline);
      this.expiryDeadline = Number.isFinite(deadline) && deadline > 0 ? deadline : null;
    }

    if (this.inFlight) {
      this.refreshRequested = true;
      return;
    }

    this.fetchSnapshot();
  }

  async fetchSnapshot() {
    if (this.inFlight) {
      this.refreshRequested = true;
      return;
    }

    this.refreshRequested = false;
    this.activeRequestIds = this.refreshRequestIds;
    this.refreshRequestIds = new Set();
    const requestStartedAt = Date.now();
    this.dispatch("refreshing");
    const request = fetchJson(`/api/v1/events/${encodeURIComponent(this.eventId)}`, {
      cache: "no-store",
    });
    this.inFlight = request;

    try {
      const { data: event } = await request;
      const crossedExpiry =
        this.expiryDeadline !== null &&
        requestStartedAt < this.expiryDeadline &&
        Date.now() >= this.expiryDeadline;

      if (crossedExpiry || this.refreshRequested) {
        this.refreshRequested = true;
        this.refreshRequestIds = new Set([...this.activeRequestIds, ...this.refreshRequestIds]);
      } else {
        this.dispatch("updated", {
          detail: { event, requestIds: [...this.activeRequestIds] },
        });
      }
    } catch (error) {
      if (this.refreshRequested) {
        this.refreshRequestIds = new Set([...this.activeRequestIds, ...this.refreshRequestIds]);
      } else {
        this.dispatch("failed", {
          detail: { error, requestIds: [...this.activeRequestIds] },
        });
      }
    } finally {
      this.inFlight = null;
      this.activeRequestIds.clear();
      if (this.refreshRequested) this.fetchSnapshot();
    }
  }
}
