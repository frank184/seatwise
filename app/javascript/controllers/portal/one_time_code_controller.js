import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  submitWhenComplete() {
    const form = this.element.form;
    if (!form || this.submitting || !/^\d{6}$/.test(this.element.value)) return;

    this.submitting = true;
    form.requestSubmit();
  }
}
