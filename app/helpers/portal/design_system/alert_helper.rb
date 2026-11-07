module Portal
  module DesignSystem
    module AlertHelper
      ALERT_VARIANTS = %i[info success warning error].freeze

      def status_alert(
        title:,
        description:,
        variant: :info,
        icon: nil,
        soft: false,
        action: nil,
        role: "alert",
        extra_class: nil
      )
        variant = variant.to_sym
        variant = :info unless ALERT_VARIANTS.include?(variant)

        message_parts = [tag.h4(title, class: "font-semibold")]
        message_parts << tag.p(description, class: "text-sm") if description.present?
        message = safe_join(message_parts)
        parts = []
        parts << lucide(icon, class: "size-5 shrink-0") if icon.present?
        parts << content_tag(:div, message)
        parts << action if action.present?

        content_tag(
          :div,
          safe_join(parts),
          role: role,
          class: class_names("alert", "alert-#{variant}", ("alert-soft" if soft), extra_class)
        )
      end
    end
  end
end
