module Portal
  module DesignSystem
    module TableHelper
      def data_table(
        headers:,
        rows:,
        size: :sm,
        zebra: false,
        row_header: true,
        wrapper_class: nil,
        table_class: nil
      )
        head = tag.thead { tag.tr(safe_join(headers.map { |header| tag.th(header) })) }

        body =
          tag.tbody do
            safe_join(
              rows.map do |row|
                cells =
                  row.each_with_index.map do |cell, index|
                    row_header && index.zero? ? tag.th(cell, scope: "row") : tag.td(cell)
                  end
                tag.tr(safe_join(cells))
              end
            )
          end

        table =
          tag.table(
            safe_join([head, body]),
            class:
              class_names(
                "table",
                ("table-#{size}" if size.present?),
                ("table-zebra" if zebra),
                table_class
              )
          )
        content_tag(
          :div,
          table,
          class: class_names("overflow-x-auto rounded-box border border-base-300", wrapper_class)
        )
      end
    end
  end
end
