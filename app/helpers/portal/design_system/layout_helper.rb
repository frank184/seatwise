module Portal
  module DesignSystem
    module LayoutHelper
      def card(
        title: nil,
        description: nil,
        body_class: nil,
        title_class: nil,
        description_class: nil,
        card_class: "card-border bg-base-100 shadow-sm",
        element: :div,
        body: true,
        &block
      )
        content = capture(&block)
        content =
          card_body(
            body_class: body_class,
            title: title,
            description: description,
            title_class: title_class,
            description_class: description_class
          ) { content } if body
        content_tag(element, content, class: class_names("card", card_class))
      end

      def card_body(
        title: nil,
        description: nil,
        body_class: nil,
        title_class: nil,
        description_class: nil,
        &block
      )
        body_parts = []
        body_parts << tag.h3(title, class: class_names("card-title", title_class)) if title.present?
        if description.present?
          body_parts << tag.p(
            description,
            class: class_names("text-sm text-base-content/60", description_class)
          )
        end
        body_parts << capture(&block) if block
        content_tag(:div, safe_join(body_parts), class: class_names("card-body", body_class))
      end

      def card_title(title, extra_class: nil)
        tag.h3(title, class: class_names("card-title", extra_class))
      end

      def record_heading(title:, kind:)
        content_tag(
          :div,
          safe_join([card_title(title), tag.span(kind, class: "badge badge-outline")]),
          class: "flex items-center justify-between"
        )
      end

      def section_heading(title:, kicker: nil, description: nil, heading_id: nil)
        heading =
          tag.h2(title, id: heading_id, class: "mt-1 text-2xl font-bold tracking-tight sm:text-3xl")
        title_parts = []
        title_parts << tag.p(kicker, class: "text-sm font-semibold text-primary") if kicker.present?
        title_parts << heading
        parts = [content_tag(:div, safe_join(title_parts))]
        if description.present?
          parts << tag.p(description, class: "max-w-xl text-sm leading-6 text-base-content/60")
        end
        content_tag(
          :div,
          safe_join(parts),
          class: "flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between"
        )
      end
    end
  end
end
