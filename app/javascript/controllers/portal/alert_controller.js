import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["dialog"];

  open({ detail }) {
    this.pendingAction = detail?.action;
    if (!this.dialogTarget.open) this.dialogTarget.showModal();
  }

  confirm() {
    const action = this.pendingAction;
    this.pendingAction = null;
    this.dialogTarget.close();
    if (action) this.dispatch("confirmed", { detail: { action } });
  }

  dismiss() {
    this.pendingAction = null;
    if (this.dialogTarget.open) this.dialogTarget.close();
  }

  clearAction() {
    this.pendingAction = null;
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) this.dismiss();
  }
}
