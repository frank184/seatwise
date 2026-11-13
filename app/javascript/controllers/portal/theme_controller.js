import { Controller } from "@hotwired/stimulus";

const STORAGE_KEY = "seatwise-theme";

export default class extends Controller {
  static targets = ["control", "wordmark"];

  connect() {
    this.applyTheme(document.documentElement.dataset.theme || "light");
  }

  change({ currentTarget }) {
    this.applyTheme(currentTarget.checked ? "dark" : "light");
  }

  applyTheme(theme) {
    const normalizedTheme = theme === "dark" ? "dark" : "light";
    const root = document.documentElement;
    root.dataset.theme = normalizedTheme;
    root.classList.add("theme-switching");
    window.clearTimeout(this.transitionTimeout);
    this.transitionTimeout = window.setTimeout(() => root.classList.remove("theme-switching"), 220);

    try {
      window.localStorage.setItem(STORAGE_KEY, normalizedTheme);
    } catch (_) {
      // Theme selection still applies for this page when storage is unavailable.
    }

    if (this.hasControlTarget) this.controlTarget.checked = normalizedTheme === "dark";
    if (this.hasWordmarkTarget) {
      this.wordmarkTarget.src = this.wordmarkTarget.dataset[`${normalizedTheme}Src`];
    }
  }
}
