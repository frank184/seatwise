import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["summaryState", "summaryTitle", "summaryDescription", "checkedAt", "refreshButton", "status", "message", "latency"]

  connect() {
    this.refresh()
  }

  async refresh() {
    this.refreshButtonTarget.disabled = true
    this.summaryTitleTarget.textContent = "Checking systems…"
    this.summaryDescriptionTarget.textContent = "We’re checking the live health endpoints now."
    this.setState(this.summaryStateTarget, "checking", "Status is being checked")

    const results = await Promise.all(this.statusTargets.map((status) => this.checkService(status)))
    const allOperational = results.every(Boolean)
    this.summaryTitleTarget.textContent = allOperational ? "All systems operational" : "Some checks need attention"
    this.summaryDescriptionTarget.textContent = allOperational
      ? "The API and Rails health checks are responding normally."
      : "At least one health check did not return a successful response."
    this.setState(this.summaryStateTarget, allOperational ? "online" : "error", allOperational ? "All systems operational" : "Some checks need attention")
    this.checkedAtTarget.textContent = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit", second: "2-digit" }).format(new Date())
    this.refreshButtonTarget.disabled = false
  }

  async checkService(status) {
    const card = status.closest(".card")
    const message = card.querySelector('[data-portal--status-target="message"]')
    const latency = card.querySelector('[data-portal--status-target="latency"]')
    const startedAt = performance.now()
    const endpoint = status.dataset.endpoint
    const abortController = new AbortController()
    const timeout = window.setTimeout(() => abortController.abort(), 8000)

    status.dataset.state = "checking"
    status.setAttribute("aria-label", "Health check in progress")
    message.textContent = "Checking…"
    latency.textContent = "—"

    try {
      const response = await fetch(endpoint, {
        headers: { Accept: "application/json" },
        cache: "no-store",
        signal: abortController.signal
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      if (endpoint === "/api/v1/up") {
        const body = await response.json()
        if (body.status !== "ok" || body.api_version !== "v1") throw new Error("Unexpected API health response")
      }

      this.setState(status, "online", "Operational")
      message.textContent = "Health check passed"
      latency.textContent = `${Math.round(performance.now() - startedAt)} ms`
      return true
    } catch (error) {
      this.setState(status, "error", "Health check failed")
      message.textContent = error.name === "AbortError" ? "Check timed out" : error.message.startsWith("HTTP ") ? error.message : "Could not reach this endpoint"
      return false
    } finally {
      window.clearTimeout(timeout)
    }
  }

  setState(element, state, label) {
    const stateClasses = { checking: "status-neutral", online: "status-success", error: "status-error" }
    element.className = `status ${element === this.summaryStateTarget ? "status-lg" : "status-md"} ${stateClasses[state]}`
    element.dataset.state = state
    element.setAttribute("aria-label", label)
  }
}
