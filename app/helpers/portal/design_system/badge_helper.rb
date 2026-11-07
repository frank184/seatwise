module Portal
  module DesignSystem
    module BadgeHelper
      BADGE_VARIANTS = %i[primary secondary accent neutral info success warning error].freeze
      BADGE_STYLES = %i[outline dash soft ghost].freeze
      BADGE_SIZES = %i[xs sm md lg xl].freeze

      def badge(label, variant: nil, style: nil, size: nil, extra_class: nil)
        variant_class = "badge-#{variant}" if BADGE_VARIANTS.include?(variant&.to_sym)
        style_class = "badge-#{style}" if BADGE_STYLES.include?(style&.to_sym)
        size_class = "badge-#{size}" if BADGE_SIZES.include?(size&.to_sym)

        tag.span(
          label,
          class: class_names("badge", variant_class, style_class, size_class, extra_class)
        )
      end
    end
  end
end
