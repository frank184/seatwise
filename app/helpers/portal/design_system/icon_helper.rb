module Portal
  module DesignSystem
    module IconHelper
      def lucide(name, decorative: true, **options)
        options[:aria] = (options[:aria] || {}).merge(hidden: true) if decorative
        lucide_icon(name.to_s, **options)
      end
    end
  end
end
