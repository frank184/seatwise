module Api
  module V1
    class EventsController < BaseController
      SORTS = {
        "soonest" => "start_time asc",
        "latest" => "start_time desc",
        "name" => "name asc"
      }.freeze
      PER_PAGE = 6

      def index
        search = Event.ransack(event_search_params)
        search.sorts = SORTS.fetch(params[:sort], SORTS.fetch("soonest")) if search.sorts.empty?
        events = search.result.includes(:venue, :reservations).order(:id).page(params[:page]).per(PER_PAGE)

        render json: {
          data: events.map { |event| event_payload(event) },
          meta: {
            count: events.size,
            total_count: events.total_count,
            page: events.current_page,
            per_page: events.limit_value,
            total_pages: events.total_pages,
            next_page: events.next_page,
            previous_page: events.prev_page,
            api_version: "v1"
          }
        }
      end

      def show
        event = Event.includes(:venue, :reservations).find(params[:id])
        render json: { data: event_payload(event), meta: { api_version: "v1" } }
      end

      private

      def event_search_params
        raw_query = params[:q]
        conditions = if raw_query.is_a?(ActionController::Parameters)
          raw_query.permit(:name_or_venue_name_cont, :name_cont, :venue_name_cont, :start_time_gteq, :start_time_lt).to_h
        elsif raw_query.present?
          { name_or_venue_name_cont: raw_query.to_s }
        else
          {}
        end

        conditions[:start_time_gteq] = Time.current if params[:when] == "upcoming"
        conditions[:start_time_lt] = Time.current if params[:when] == "past"
        conditions[:s] = SORTS.fetch(params[:sort], SORTS.fetch("soonest"))
        conditions
      end

      def event_payload(event)
        rows = Array(event.layout_snapshot&.dig("rows"))
        active_reservations = event.reservations.select do |reservation|
          reservation.confirmed? || (reservation.held? && reservation.hold_expires_at&.future?)
        end
        reserved_by_row = active_reservations.group_by(&:row_id).transform_values do |reservations|
          reservations.flat_map do |reservation|
            (reservation.seat_range.begin...reservation.seat_range.end).to_a
          end
        end
        rows = rows.map do |row|
          row_id = row.fetch("row_id").to_i
          row.merge("reserved_seats" => reserved_by_row.fetch(row_id, []))
        end
        seat_count = rows.sum { |row| row.fetch("seat_count", 0).to_i }
        reserved_count = reserved_by_row.values.sum(&:size)

        {
          id: event.id,
          name: event.name,
          starts_at: event.start_time.iso8601,
          ends_at: event.end_time.iso8601,
          past: event.start_time < Time.current,
          venue: { name: event.venue.name },
          rows: rows,
          seat_count: seat_count,
          reserved_count: reserved_count,
          available_count: [seat_count - reserved_count, 0].max
        }
      end
    end
  end
end
