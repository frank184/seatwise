module Portal
  module DesignSystem
    module FieldHelper
      def field(
        label:,
        name:,
        type: "text",
        value: nil,
        placeholder: nil,
        required: false,
        hint: nil,
        error: nil,
        id: nil,
        input_class: nil
      )
        field_id = id.presence || name.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")
        hint_id = "#{field_id}_hint" if hint.present?
        error_id = "#{field_id}_error" if error.present?
        label_parts = [label]
        label_parts << tag.span(" *", class: "text-error") if required

        input =
          tag.input(
            type: type,
            name: name,
            id: field_id,
            value: value,
            placeholder: placeholder,
            required: required,
            class:
              class_names(
                "input input-bordered w-full",
                ("input-error" if error.present?),
                input_class
              ),
            aria: {
              invalid: ("true" if error.present?),
              describedby: [hint_id, error_id].compact.join(" ").presence
            }
          )

        parts = [tag.span(safe_join(label_parts), class: "label-text mb-2 font-medium"), input]
        if hint.present?
          parts << tag.span(hint, id: hint_id, class: "label mt-1 text-base-content/55")
        end
        parts << tag.span(error, id: error_id, class: "label -mt-2 text-error") if error.present?
        content_tag(:label, safe_join(parts), class: "form-control w-full", for: field_id)
      end
    end
  end
end
