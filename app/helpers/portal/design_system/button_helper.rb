module Portal
  module DesignSystem
    module ButtonHelper
      BUTTON_VARIANTS = {
        default: "btn",
        primary: "btn btn-primary",
        outline: "btn btn-outline",
        ghost: "btn btn-ghost",
        error: "btn btn-error"
      }.freeze

      BUTTON_SIZES = { xs: "btn-xs", sm: "btn-sm", lg: "btn-lg" }.freeze

      def button(
        label = nil,
        variant: :default,
        size: nil,
        href: nil,
        type: "button",
        **options,
        &block
      )
        classes = [
          BUTTON_VARIANTS.fetch(variant.to_sym, BUTTON_VARIANTS[:default]),
          BUTTON_SIZES[size&.to_sym],
          options.delete(:class)
        ]
        options[:class] = class_names(*classes)
        content = block ? capture(&block) : label

        href ? link_to(content, href, **options) : button_tag(content, type: type, **options)
      end
    end
  end
end
