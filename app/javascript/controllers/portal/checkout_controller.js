import { Controller } from "@hotwired/stimulus";
import { fetchJson } from "controllers/portal/view_helpers";

export default class extends Controller {
  connect() {
    this.generation = 0;
    this.setupPromise = null;
    this.reservation = null;
    this.paymentSession = null;
    this.stage = null;
    this.pollingId = null;
    this.elementsMounted = false;
    this.expressElementMounted = false;
    this.paymentElementMounted = false;
    this.paymentElementReady = false;
    this.walletMethodsAvailable = null;
  }

  disconnect() {
    this.generation += 1;
    this.pollingId = null;
    this.unmountElements();
  }

  setup({ detail }) {
    const reservation = detail?.reservation;
    if (!reservation || reservation.status !== "held") {
      this.emit("failed", {
        requestId: detail?.requestId,
        error: "Your hold is no longer active.",
      });
      return;
    }
    if (this.setupPromise && this.reservation?.id === reservation.id) return;

    this.reservation = reservation;
    this.paymentSession = detail.paymentSession || this.paymentSession;
    this.setupPromise = this.createCheckout(detail).finally(() => {
      this.setupPromise = null;
    });
  }

  async createCheckout({ requestId }) {
    const generation = ++this.generation;
    this.activeRequestId = requestId;
    const reservation = this.reservation;
    this.unmountElements();
    this.clearElements();
    this.checkout = null;
    this.checkoutActions = null;
    this.setStatus("Loading payment options…");
    this.setError("");
    this.setRetryVisible(false);
    this.setLoading(true);
    this.setPayDisabled(true);

    let provider;
    try {
      const organizationResponse = await fetchJson("/api/v1/organizations/development");
      provider = organizationResponse.data?.payment_provider;
      if (!provider?.enabled || provider.provider_key !== "stripe" || !provider.publishable_key) {
        throw new Error(
          "Online payment is temporarily unavailable. Your seats remain held while you try again.",
        );
      }
      this.assertCurrent(generation, reservation);
      if (reservation.expiresAt <= Date.now()) throw new Error("Your hold has expired.");

      await this.waitForStripe();
      this.assertCurrent(generation, reservation);
      const stripe = window.Stripe(provider.publishable_key);
      if (!stripe)
        throw new Error("Online payment is temporarily unavailable. Please try again shortly.");

      const sessionResponse = await fetchJson(
        `/api/v1/reservations/${encodeURIComponent(reservation.id)}/checkout/session`,
        { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" },
      );
      const session = sessionResponse.data || sessionResponse;
      if (!session.client_secret)
        throw new Error("We couldn’t start secure checkout. Your seats remain held.");
      this.assertCurrent(generation, reservation);
      if (reservation.expiresAt <= Date.now()) throw new Error("Your hold has expired.");

      this.paymentSession = {
        session_id: session.session_id,
        amount: session.amount,
        currency: session.currency,
        status: session.status,
      };
      this.renderPaymentTotal(session.amount, session.currency);
      this.checkout = stripe.initCheckoutElementsSdk({
        clientSecret: session.client_secret,
        elementsOptions: {
          appearance: {
            theme: document.documentElement.dataset.theme === "dark" ? "night" : "stripe",
            inputs: "condensed",
            labels: "auto",
          },
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
      this.assertCurrent(generation, reservation);
      if (actionsResult.type !== "success")
        throw new Error("Secure payment couldn’t be loaded. Your seats remain held.");
      this.checkoutActions = actionsResult.actions;
      this.mountElements();
      this.setStatus("Enter your payment details to finish booking.");
      this.activeRequestId = null;
      this.emit("ready", {
        requestId,
        provider: { ...provider, enabled: true },
        paymentSession: this.paymentSession,
      });
    } catch (failure) {
      if (generation !== this.generation) return;
      this.activeRequestId = null;
      this.setPayDisabled(true);
      this.setRetryVisible(true);
      this.setStatus("Payment setup didn’t finish. Your seats remain held.", true);
      this.showError(
        failure.message || "Online payment is temporarily unavailable. Your seats remain held.",
      );
      this.emit("failed", {
        requestId,
        provider,
        paymentSession: this.paymentSession,
        error: failure.message,
      });
    } finally {
      if (generation === this.generation) this.setLoading(false);
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
        window.Stripe
          ? resolve()
          : reject(new Error("Secure payment couldn’t be loaded. Please try again shortly."));
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
  }

  mountElements() {
    if (this.stage !== "payment" || this.elementsMounted) return;
    const region = this.element.querySelector("[data-express-checkout-region]");
    const target = this.element.querySelector("[data-express-checkout-element]");
    const fallback = this.element.querySelector("[data-wallet-availability]");
    this.paymentElementReady = false;
    this.walletMethodsAvailable = null;
    delete this.element.dataset.paymentReady;
    if (!this.expressCheckoutElement) {
      this.expressCheckoutElement = this.checkout.createExpressCheckoutElement({
        buttonType: { applePay: "buy", googlePay: "buy", paypal: "buynow" },
        paymentMethods: { googlePay: "always" },
      });
      this.expressCheckoutElement.on("ready", ({ availablePaymentMethods }) => {
        this.walletMethodsAvailable = Boolean(
          availablePaymentMethods && Object.values(availablePaymentMethods).some(Boolean),
        );
        this.updateWalletAvailability(region, fallback);
      });
      this.expressCheckoutElement.on("loaderror", () =>
        this.handleElementLoadError(this.generation),
      );
      this.expressCheckoutElement.on("confirm", (event) => this.confirm(event, this.generation));
    }
    this.expressCheckoutElement.mount(target);
    this.expressElementMounted = true;

    const paymentTarget = this.element.querySelector("[data-payment-element]");
    if (!this.paymentElement) {
      paymentTarget.replaceChildren();
      this.paymentElement = this.checkout.createPaymentElement({ layout: { type: "accordion" } });
      this.paymentElement.on("ready", () => {
        this.paymentElementReady = true;
        this.element.dataset.paymentReady = "true";
        this.updateWalletAvailability(region, fallback);
        if (this.stage === "payment") this.setPayDisabled(false);
      });
      this.paymentElement.on("loaderror", () => this.handleElementLoadError(this.generation));
    }
    this.setPayDisabled(true);
    this.paymentElement.mount(paymentTarget);
    this.paymentElementMounted = true;
    this.elementsMounted = true;
  }

  handleElementLoadError(generation) {
    if (generation !== this.generation) return;
    this.paymentElementReady = false;
    delete this.element.dataset.paymentReady;
    this.setPayDisabled(true);
    this.setRetryVisible(true);
    this.setStatus("Secure payment couldn’t be loaded. Your seats remain held.", true);
    this.showError("Secure payment couldn’t be loaded. Please try again.");
    this.emit("failed", {
      kind: "element_load_error",
      error: "Secure payment couldn’t be loaded.",
    });
  }

  updateWalletAvailability(region, fallback) {
    const ready = this.paymentElementReady && this.walletMethodsAvailable !== null;
    region.hidden = !ready || !this.walletMethodsAvailable;
    fallback.hidden = !ready || this.walletMethodsAvailable;
  }

  stageChanged({ detail }) {
    const previousStage = this.stage;
    this.stage = detail?.stage;
    this.reservation = detail?.reservation || this.reservation;
    if (this.stage !== "payment" && this.stage !== "redirecting") {
      this.unmountElements();
      if (previousStage === "payment" && this.activeRequestId) {
        const requestId = this.activeRequestId;
        this.activeRequestId = null;
        this.generation += 1;
        this.emit("failed", {
          requestId,
          interrupted: true,
          error: "Checkout setup was interrupted.",
        });
      }
    } else if (this.stage === "payment" && this.checkoutActions) this.mountElements();
  }

  reset() {
    this.generation += 1;
    this.pollingId = null;
    this.setupPromise = null;
    this.unmountElements();
    this.clearElements();
    this.checkout = null;
    this.checkoutActions = null;
    this.reservation = null;
    this.paymentSession = null;
  }

  restore({ detail }) {
    this.reservation = detail.reservation;
    this.paymentSession = { ...(detail.paymentSession || {}), session_id: detail.sessionId };
    if (!this.reservation) {
      this.showReturnStatus(
        "We couldn’t restore this reservation in your browser. Check your booking email for an update.",
      );
      return;
    }
    this.pollStatus(detail.sessionId);
  }

  poll({ detail }) {
    this.reservation = detail.reservation || this.reservation;
    this.paymentSession = detail.paymentSession || this.paymentSession;
    if (detail.sessionId) this.pollStatus(detail.sessionId);
  }

  async checkStatus() {
    const sessionId =
      new URLSearchParams(window.location.search).get("session_id") ||
      this.paymentSession?.session_id;
    if (sessionId) await this.pollStatus(sessionId);
  }

  async pollStatus(sessionId) {
    const reservation = this.reservation;
    if (!reservation) return;
    const pollingId = Symbol("checkout-status-poll");
    this.pollingId = pollingId;
    const deadline = Date.now() + 120_000;
    const retryButton = this.element.querySelector("[data-check-payment-status]");
    retryButton.hidden = true;
    while (this.pollingId === pollingId && Date.now() < deadline) {
      try {
        const response = await fetchJson(
          `/api/v1/reservations/${encodeURIComponent(reservation.id)}/checkout?session_id=${encodeURIComponent(sessionId)}`,
        );
        if (this.pollingId !== pollingId) return;
        const result = response.data || response;
        if (result.status === "succeeded") {
          this.clearReturnParams();
          this.emit("confirmed", { result });
          return;
        }
        if (result.status === "failed") {
          this.clearReturnParams();
          this.showError(
            "That payment didn’t go through. Your seats are still held; try another payment method.",
          );
          this.emit("failed", { result, error: "Payment failed." });
          return;
        }
        if (result.status === "expired") {
          this.clearReturnParams();
          this.emit("expired", { result });
          return;
        }
        this.showReturnStatus(
          "Your payment is processing. We’re waiting for Stripe to confirm it.",
        );
      } catch (_failure) {
        this.showReturnStatus(
          "We’re having trouble checking the payment status. We’ll keep trying.",
        );
      }
      await new Promise((resolve) => setTimeout(resolve, 1500));
    }
    if (this.pollingId === pollingId) {
      if (reservation.expiresAt <= Date.now()) this.emit("expired", { result: null });
      else
        this.showReturnStatus(
          "Your payment is still being confirmed. You can check again in a moment.",
          true,
        );
    }
  }

  async confirmPayment(event) {
    event.preventDefault();
    return this.confirm();
  }

  async confirm(expressEvent = null, generation = this.generation) {
    const reservation = this.reservation;
    if (
      this.stage !== "payment" ||
      !reservation ||
      reservation.status !== "held" ||
      !this.checkoutActions
    )
      return;
    if (reservation.expiresAt <= Date.now()) {
      this.emit("expired", { result: null });
      return;
    }
    this.setError("");
    this.emit("redirecting", { payment: { status: "processing", startedAt: Date.now() } });
    try {
      const options = { redirect: "if_required" };
      if (expressEvent) options.expressCheckoutConfirmEvent = expressEvent;
      const result = await this.checkoutActions.confirm(options);
      if (generation !== this.generation) return;
      if (result.type === "error") {
        this.showError(
          result.error?.message ||
            "Your payment couldn’t be completed. Try another payment method.",
        );
        this.emit("failed", { result, error: result.error?.message });
        return;
      }
      this.emit("redirecting", { payment: { status: "processing", receivedAt: Date.now() } });
      if (this.paymentSession?.session_id) this.pollStatus(this.paymentSession.session_id);
    } catch (failure) {
      if (generation !== this.generation) return;
      console.error("Stripe checkout confirmation threw an error", {
        name: failure?.name,
        message: failure?.message,
      });
      this.showError(
        "We couldn’t confirm that payment. Your hold is still active; please try again.",
      );
      this.emit("failed", { error: failure.message });
    }
  }

  retrySetup(event) {
    event.currentTarget.disabled = true;
    this.setup({
      detail: {
        requestId: null,
        reservation: this.reservation,
        paymentSession: this.paymentSession,
      },
    });
  }

  renderPaymentTotal(amount, currency) {
    const total = this.element.querySelector("[data-reservation-total]");
    if (!total || !Number.isFinite(Number(amount)) || !currency) return;
    total.textContent = new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: currency.toUpperCase(),
    }).format(Number(amount) / 100);
  }

  assertCurrent(generation, reservation) {
    if (generation !== this.generation || this.reservation?.id !== reservation.id) {
      throw new Error("Checkout setup was superseded.");
    }
  }

  unmountElements() {
    if (this.paymentElementMounted) this.paymentElement?.unmount?.();
    if (this.expressElementMounted) this.expressCheckoutElement?.unmount?.();
    this.elementsMounted = false;
    this.expressElementMounted = false;
    this.paymentElementMounted = false;
    this.paymentElementReady = false;
    this.walletMethodsAvailable = null;
    delete this.element.dataset.paymentReady;
  }

  clearElements() {
    this.unmountElements();
    this.paymentElement = null;
    this.expressCheckoutElement = null;
  }

  emit(name, detail = {}) {
    this.dispatch(name, { detail });
  }

  setLoading(loading) {
    const element = this.element.querySelector("[data-payment-loading]");
    if (element) element.hidden = !loading;
  }

  setStatus(message, error = false) {
    const status = this.element.querySelector("[data-payment-status]");
    if (!status) return;
    status.textContent = message;
    status.hidden = false;
    status.classList.toggle("text-error", error);
  }

  setPayDisabled(disabled) {
    const button = this.element.querySelector("[data-payment-submit]");
    if (button) button.disabled = disabled;
  }

  setRetryVisible(visible) {
    const button = this.element.querySelector("[data-payment-retry]");
    if (button) {
      button.hidden = !visible;
      button.disabled = false;
    }
  }

  setError(message) {
    const error = this.element.querySelector("[data-payment-error]");
    if (error) {
      error.textContent = message;
      error.hidden = !message;
    }
  }

  showError(message) {
    const status = this.element.querySelector("[data-payment-status]");
    if (status) status.hidden = true;
    this.setError(message);
  }

  showReturnStatus(message, retry = false) {
    const status = this.element.querySelector("[data-checkout-return-status]");
    const button = this.element.querySelector("[data-check-payment-status]");
    if (status) status.textContent = message;
    if (button) button.hidden = !retry;
  }

  clearReturnParams() {
    const url = new URL(window.location.href);
    url.searchParams.delete("session_id");
    url.searchParams.delete("reservation_id");
    window.history.replaceState({}, "", url);
  }
}
