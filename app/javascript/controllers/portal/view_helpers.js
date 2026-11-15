import dayjs from "dayjs";
import relativeTime from "dayjs/plugin/relativeTime";

dayjs.extend(relativeTime);

export async function fetchJson(url, options = {}) {
  const response = await fetch(url, {
    headers: { Accept: "application/json", ...options.headers },
    ...options,
  });
  const body = await response.json();
  if (!response.ok) {
    const error = new Error(body.error?.message || `Request failed (${response.status})`);
    error.status = response.status;
    error.code = body.error?.code;
    throw error;
  }
  return body;
}

export function cloneTemplate(root, selector) {
  return root.querySelector(selector).content.firstElementChild.cloneNode(true);
}

export function formatDate(value, options) {
  return new Intl.DateTimeFormat(undefined, options).format(new Date(value));
}

export function formatRelativeTime(value) {
  if (value == null || value === "") return "";

  const date = dayjs(value);
  return date.isValid() ? date.fromNow() : "";
}
