module Portal
  module DesignSystem
    module StatusHelper
      def status_badge(label, variant: :ghost, small: false, soft: false)
        style = :soft if soft
        style ||= :ghost if variant.to_sym == :ghost
        badge(
          label,
          variant: (variant unless variant.to_sym == :ghost),
          style: style,
          size: (:sm if small)
        )
      end
    end
  end
end
