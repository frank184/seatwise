# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin "dayjs", to: "https://cdn.jsdelivr.net/npm/dayjs@1.11.23/+esm"
pin "dayjs/plugin/relativeTime",
    to: "https://cdn.jsdelivr.net/npm/dayjs@1.11.23/plugin/relativeTime/+esm"
pin_all_from "app/javascript/channels", under: "channels"
pin_all_from "app/javascript/controllers", under: "controllers"
