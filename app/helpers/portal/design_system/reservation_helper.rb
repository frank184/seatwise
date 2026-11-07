module Portal
  module DesignSystem
    module ReservationHelper
      def step_indicator(steps:, current_step:, label: "Booking progress")
        items =
          steps.each_with_index.map do |step, index|
            step_number = index + 1
            attributes = {
              class: class_names("step", ("step-primary" if step_number <= current_step.to_i))
            }
            attributes["aria-current"] = "step" if step_number == current_step.to_i
            tag.li(step, **attributes)
          end

        tag.ul(
          safe_join(items),
          class: "steps steps-horizontal w-full text-xs sm:text-sm",
          aria: {
            label: label
          }
        )
      end

      def reservation_summary(
        event_name:,
        event_date:,
        row_id:,
        row_label:,
        seat_start:,
        seat_end:,
        status_label:,
        status_variant:,
        hold_deadline: nil,
        total: nil,
        editable: false
      )
        heading =
          content_tag(:div) do
            safe_join(
              [
                tag.p(
                  "Your reservation",
                  class: "text-xs font-semibold uppercase tracking-wider text-base-content/50"
                ),
                tag.h3(event_name, class: "mt-1 font-bold"),
                tag.p(event_date, class: "mt-1 text-sm text-base-content/60")
              ]
            )
          end
        heading_parts = [heading]
        heading_parts << button("Edit", size: :xs, variant: :ghost) if editable
        rows = [
          content_tag(
            :div,
            safe_join(
              [
                tag.dt("Seats", class: "text-base-content/60"),
                tag.dd(class: "text-right") do
                  safe_join(
                    [
                      tag.span(
                        "Row #{row_label} · #{seat_start}–#{seat_end}",
                        class: "font-semibold"
                      ),
                      tag.span(
                        "row_id: #{row_id}",
                        class: "block font-mono text-xs text-base-content/55"
                      )
                    ]
                  )
                end
              ]
            ),
            class: "flex justify-between gap-4"
          ),
          content_tag(
            :div,
            safe_join(
              [
                tag.dt("Reservation", class: "text-base-content/60"),
                tag.dd(status_badge(status_label, variant: status_variant))
              ]
            ),
            class: "flex justify-between gap-4"
          )
        ]
        if hold_deadline.present?
          rows << content_tag(
            :div,
            safe_join(
              [
                tag.dt("Hold deadline", class: "text-base-content/60"),
                tag.dd(hold_deadline, class: "font-medium")
              ]
            ),
            class: "flex justify-between gap-4"
          )
        end
        summary_parts = [
          content_tag(
            :div,
            safe_join(heading_parts),
            class: "flex items-start justify-between gap-3"
          ),
          tag.div(class: "my-4 border-t border-base-300"),
          content_tag(:dl, safe_join(rows), class: "space-y-2 text-sm")
        ]
        if total.present?
          summary_parts.concat(
            [
              tag.div(class: "my-4 border-t border-base-300"),
              content_tag(
                :div,
                safe_join([tag.span("Estimated total"), tag.span(total)]),
                class: "flex justify-between font-semibold"
              )
            ]
          )
        end
        content_tag(
          :div,
          safe_join(summary_parts),
          class: "rounded-box border border-base-300 bg-base-200 p-5"
        )
      end
    end
  end
end
