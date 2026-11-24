require "digest"
require "set"

module Api
  module V1
    class ReservationsController < BaseController
      HOLD_DURATION = 5.minutes
      MAX_QUANTITY = 6
      PER_PAGE = 10

      def index
        return unless require_customer_scope!("reservations:read")

        response.headers["Cache-Control"] = "no-store"
        expire_due_holds
        reservations = current_customer.reservations.includes(event: :venue)
        reservations = filter_reservations(reservations)
        total_count = reservations.count
        total_pages = (total_count.to_f / PER_PAGE).ceil
        requested_page = params[:page].to_s.to_i
        page = [[requested_page, 1].max, [total_pages, 1].max].min
        reservations = reservations.order(created_at: :desc, id: :desc).page(page).per(PER_PAGE)

        render json: {
                 data: reservations.map { |reservation| reservation_payload(reservation) },
                 meta: {
                   count: reservations.size,
                   total_count:,
                   page: reservations.current_page,
                   per_page: reservations.limit_value,
                   total_pages:,
                   next_page: reservations.next_page,
                   previous_page: reservations.prev_page,
                   venues: reservation_venues,
                   api_version: "v1"
                 }
               }
      end

      def show
        return unless require_customer_scope!("reservations:read")

        reservation = current_customer.reservations.find(params[:id])
        response.headers["Cache-Control"] = "no-store"
        render json: reservation_payload(reservation)
      rescue ActiveRecord::RecordNotFound
        render_error("Reservation not found", :not_found)
      end

      def create
        if bearer_request?
          return unless require_customer_scope!("reservations:manage")
        end

        event_id = params[:event_id]
        quantity = params[:quantity]
        submitted_email = params[:email].to_s.strip.downcase
        email = current_customer ? current_customer.email : submitted_email
        idempotency_key = request.headers["Idempotency-Key"].to_s.strip
        coordinates_provided = %i[row_id seat_start seat_end].any? { |key| params.key?(key) }

        if current_customer &&
             (
               (submitted_email.present? && submitted_email != current_customer.email) ||
                 (
                   params[:customer_id].present? &&
                     params[:customer_id].to_s != current_customer.id.to_s
                 )
             )
          render_error(
            "Reservation customer does not match the authenticated customer",
            :unprocessable_entity
          )
          return
        end

        unless event_id.is_a?(Integer) ? event_id.positive? : event_id.to_s.match?(/\A[1-9]\d*\z/)
          return render_error("event_id must be a positive integer", :unprocessable_entity)
        end
        unless email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
          return render_error("a valid email is required", :unprocessable_entity)
        end
        unless quantity.is_a?(Integer) && quantity.between?(1, MAX_QUANTITY)
          return render_error("quantity must be an integer from 1 to 6", :unprocessable_entity)
        end
        if coordinates_provided
          coordinates = [params[:row_id], params[:seat_start], params[:seat_end]]
          unless coordinates.all? { |value| value.is_a?(Integer) && value.positive? }
            message = "row_id, seat_start, and seat_end must be positive integers"
            return render_error(message, :unprocessable_entity)
          end
          unless params[:seat_end] >= params[:seat_start] &&
                   params[:seat_end] - params[:seat_start] + 1 == quantity
            return render_error("seat range must match quantity", :unprocessable_entity)
          end
        end
        return render_error("Idempotency-Key is required", :bad_request) if idempotency_key.blank?
        if idempotency_key.length > 255
          return render_error("Idempotency-Key is too long", :bad_request)
        end

        guest = current_customer ? portal_guest_capability : current_guest
        return unless require_guest_or_customer!

        event = Event.find(event_id)
        selected_row =
          if coordinates_provided
            event.rows.find { |row| row.fetch("row_id").to_i == params[:row_id] }
          end
        if coordinates_provided &&
             (!selected_row || params[:seat_end] > selected_row.fetch("seat_count", 0).to_i)
          return render_error("The selected row or seats do not exist", :unprocessable_entity)
        end

        actor_fingerprint =
          (guest.present? ? "guest:#{guest.id}" : "customer:#{current_customer.id}")
        request_details = [event.id, quantity, email, actor_fingerprint]
        if coordinates_provided
          request_details.concat([params[:row_id], params[:seat_start], params[:seat_end]])
        end
        fingerprint = Digest::SHA256.hexdigest(request_details.join("\0"))
        reservation = nil
        replay = false
        conflict = nil

        event.with_lock do
          reservation = event.reservations.find_by(idempotency_key: idempotency_key)
          if reservation
            if reservation.request_fingerprint == fingerprint
              replay = true
            else
              conflict = "Idempotency-Key was already used with different booking details"
            end
          else
            now = Time.current
            event
              .reservations
              .where(status: :held)
              .where("hold_expires_at <= ?", now)
              .update_all(status: Reservation.statuses.fetch("expired"), updated_at: now)

            allocation =
              if coordinates_provided
                blocked =
                  event
                    .reservations
                    .active_for_inventory
                    .where(row_id: params[:row_id])
                    .flat_map { |active_reservation| active_reservation.seat_range.to_a }
                    .to_set
                requested_seats = (params[:seat_start]..params[:seat_end]).to_a
                if requested_seats.any? { |seat| blocked.include?(seat) }
                  conflict = "Those seats are no longer available"
                  nil
                else
                  [selected_row, params[:seat_start]]
                end
              else
                allocation_for(event, quantity)
              end
            if allocation && allocation.first
              row, first_seat = allocation
              customer = current_customer || Customer.find_or_create_by!(email: email)
              reservation =
                event.reservations.create!(
                  customer: customer,
                  guest: guest,
                  row_id: row.fetch("row_id").to_i,
                  seat_range: first_seat...(first_seat + quantity),
                  status: :held,
                  hold_expires_at: now + HOLD_DURATION,
                  idempotency_key: idempotency_key,
                  request_fingerprint: fingerprint
                )
            elsif conflict.nil?
              conflict = "No adjacent seats are available"
            end
          end
        end

        return render_error(conflict, :conflict) if conflict
        schedule_expiration(reservation) if reservation.held? && !replay

        response.headers["Cache-Control"] = "no-store"
        render json: reservation_payload(reservation), status: replay ? :ok : :created
      rescue ActiveRecord::RecordNotFound
        render_error("Event not found", :not_found)
      rescue ActiveRecord::RecordNotUnique
        render_error(
          "Reservation request could not be replayed safely; retry with the same Idempotency-Key",
          :conflict
        )
      rescue ActiveRecord::StatementInvalid => error
        raise unless error.cause.is_a?(PG::ExclusionViolation)

        render_error("Those seats were just claimed; retry with a new Idempotency-Key", :conflict)
      end

      def destroy
        if bearer_request?
          return unless require_customer_scope!("reservations:manage")
        else
          return unless require_guest_or_customer!
        end

        reservation = find_reservation_for_current_customer(params[:id])
        return unless authorize_guest_reservation(reservation)
        unless reservation_policy(reservation).cancel?
          return render_error("Only active holds can be cancelled", :conflict)
        end

        reservation.with_lock { reservation.update!(status: :cancelled) if reservation.held? }
        response.headers["Cache-Control"] = "no-store"
        render json: { id: reservation.id, status: reservation.status }
      rescue ActiveRecord::RecordNotFound
        render_error("Reservation not found", :not_found)
      end

      private

      def portal_guest_capability
        Guest.resolve(request.headers["X-Seatwise-Guest-Token"])
      end

      def filter_reservations(reservations)
        case params[:status]
        when "active"
          reservations = reservations.where(status: %i[held confirmed])
        when "history"
          reservations = reservations.where(status: %i[expired cancelled])
        when "held", "confirmed", "cancelled", "expired"
          reservations = reservations.where(status: params[:status])
        end

        if params[:venue_id].present?
          venue_id = Integer(params[:venue_id], 10)
          reservations = reservations.joins(event: :venue).where(venues: { id: venue_id })
        end

        query = params[:q].to_s.strip
        return reservations if query.blank?

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
        reservations.joins(event: :venue).where(
          "CAST(reservations.id AS TEXT) ILIKE :query OR events.name ILIKE :query OR venues.name ILIKE :query",
          query: pattern
        )
      rescue ArgumentError
        reservations.none
      end

      def expire_due_holds
        current_customer
          .reservations
          .where(status: :held)
          .where("hold_expires_at <= ?", Time.current)
          .find_each { |reservation| Reservations::ExpireIfDue.call(reservation:) }
      end

      def reservation_venues
        current_customer
          .reservations
          .joins(event: :venue)
          .distinct
          .order("venues.name")
          .pluck("venues.id", "venues.name")
          .map { |id, name| { id:, name: } }
      end

      def schedule_expiration(reservation)
        ExpireReservationJob.set(wait_until: reservation.hold_expires_at).perform_later(
          reservation.id
        )
      rescue StandardError => error
        Rails.logger.error(
          "Could not enqueue expiry for reservation #{reservation.id}: #{error.class}"
        )
      end

      def allocation_for(event, quantity)
        blocked_by_row =
          event
            .reservations
            .active_for_inventory
            .group_by(&:row_id)
            .transform_values do |reservations|
              reservations.flat_map { |reservation| reservation.seat_range.to_a }.to_set
            end

        event
          .rows
          .sort_by { |row| row.fetch("allocation_order", 0).to_i }
          .each do |row|
            capacity = row.fetch("seat_count", 0).to_i
            blocked = blocked_by_row.fetch(row.fetch("row_id").to_i, Set.new)
            (1..(capacity - quantity + 1)).each do |first_seat|
              if (first_seat...(first_seat + quantity)).none? { |seat| blocked.include?(seat) }
                return row, first_seat
              end
            end
          end

        [nil, nil]
      end

      def reservation_payload(reservation)
        {
          id: reservation.id,
          event_id: reservation.event_id,
          event: {
            id: reservation.event.id,
            name: reservation.event.name,
            starts_at: reservation.event.start_time.iso8601,
            ends_at: reservation.event.end_time.iso8601,
            venue: {
              name: reservation.event.venue.name
            }
          },
          row_id: reservation.row_id,
          seat_start: reservation.seat_range.begin,
          seat_end: reservation.seat_range.end - 1,
          status: reservation.status,
          expires_at: reservation.hold_expires_at&.iso8601
        }
      end

      def render_error(message, status)
        render json: { error: { code: status.to_s, message: message } }, status: status
      end
    end
  end
end
