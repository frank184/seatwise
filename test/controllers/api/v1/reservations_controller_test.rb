require "test_helper"

module Api
  module V1
    class ReservationsControllerTest < ActionDispatch::IntegrationTest
      include ActiveSupport::Testing::TimeHelpers

      setup do
        travel_to Time.zone.local(2026, 11, 9, 12)
        @event = Event.create!(
          venue: venues(:one),
          name: "Reservation API test",
          start_time: 1.day.from_now,
          end_time: 1.day.from_now + 2.hours,
          ticket_price_cents: 1_000,
          layout_snapshot: {
            "rows" => [
              { "row_id" => 17, "label" => "Front", "allocation_order" => 1, "seat_count" => 8 },
              { "row_id" => 29, "label" => "Rear", "allocation_order" => 2, "seat_count" => 8 }
            ]
          }
        )
      end

      teardown { travel_back }

      test "creates one five-minute hold with the server-allocated adjacent seats" do
        post api_v1_reservations_path,
             params: { event_id: @event.id, quantity: 3, email: "  Buyer@Example.com  " },
             headers: { "Idempotency-Key" => "reservation-create-1" },
             as: :json

        assert_response :created
        assert_equal "no-store", response.headers["Cache-Control"]
        body = response.parsed_body
        assert_equal @event.id, body.fetch("event_id")
        assert_equal 17, body.fetch("row_id")
        assert_equal 1, body.fetch("seat_start")
        assert_equal 3, body.fetch("seat_end")
        assert_equal "held", body.fetch("status")
        assert_equal 5.minutes.from_now.iso8601, Time.iso8601(body.fetch("expires_at")).iso8601
        assert_equal "buyer@example.com", Reservation.find(body.fetch("id")).customer.email
      end

      test "replays the same hold for the same idempotency key and request" do
        headers = { "Idempotency-Key" => "reservation-replay-1" }
        params = { event_id: @event.id, quantity: 2, email: "buyer@example.com" }

        post api_v1_reservations_path, params: params, headers: headers, as: :json
        first_id = response.parsed_body.fetch("id")
        assert_response :created

        post api_v1_reservations_path, params: params, headers: headers, as: :json

        assert_response :ok
        assert_equal first_id, response.parsed_body.fetch("id")
        assert_equal 1, @event.reservations.where(idempotency_key: headers.fetch("Idempotency-Key")).count
      end

      test "schedules expiry once at the hold deadline and not on idempotent replay" do
        headers = { "Idempotency-Key" => "reservation-expiry-schedule-1" }
        params = { event_id: @event.id, quantity: 2, email: "buyer@example.com" }

        assert_enqueued_jobs 1, only: ExpireReservationJob do
          post api_v1_reservations_path, params:, headers:, as: :json
        end

        assert_response :created
        reservation_id = response.parsed_body.fetch("id")
        reservation = @event.reservations.find(reservation_id)
        assert_enqueued_with(
          job: ExpireReservationJob,
          args: [reservation.id],
          at: reservation.hold_expires_at
        )
        assert_no_enqueued_jobs(only: ExpireReservationJob) do
          post api_v1_reservations_path, params:, headers:, as: :json
        end

        assert_response :ok
        assert_equal reservation_id, response.parsed_body.fetch("id")
      end

      test "reuses seats from an expired hold during a new allocation" do
        old_reservation = @event.reservations.create!(
          customer: customers(:one),
          row_id: 17,
          seat_range: 1...4,
          status: :held,
          hold_expires_at: 1.second.ago
        )

        post api_v1_reservations_path,
             params: { event_id: @event.id, quantity: 3, email: "buyer@example.com" },
             headers: { "Idempotency-Key" => "reservation-reuse-expired-seats-1" },
             as: :json

        assert_response :created
        assert_equal 1, response.parsed_body.fetch("seat_start")
        assert_equal 3, response.parsed_body.fetch("seat_end")
        assert old_reservation.reload.expired?
      end

      test "rejects reuse of an idempotency key with different request details" do
        headers = { "Idempotency-Key" => "reservation-conflict-1" }
        post api_v1_reservations_path,
             params: { event_id: @event.id, quantity: 2, email: "buyer@example.com" },
             headers: headers,
             as: :json
        assert_response :created

        post api_v1_reservations_path,
             params: { event_id: @event.id, quantity: 3, email: "buyer@example.com" },
             headers: headers,
             as: :json

        assert_response :conflict
      end

      test "rejects invalid quantities and requests without an idempotency key" do
        post api_v1_reservations_path,
             params: { event_id: @event.id, quantity: 0, email: "buyer@example.com" },
             headers: { "Idempotency-Key" => "reservation-invalid-1" },
             as: :json
        assert_response :unprocessable_entity

        post api_v1_reservations_path,
             params: { event_id: @event.id, quantity: 1, email: "buyer@example.com" },
             as: :json
        assert_response :bad_request
      end

      test "rejects an unavailable quantity without creating a partial hold" do
        post api_v1_reservations_path,
             params: { event_id: @event.id, quantity: 6, email: "buyer@example.com" },
             headers: { "Idempotency-Key" => "reservation-full-1" },
             as: :json
        assert_response :created

        post api_v1_reservations_path,
             params: { event_id: @event.id, quantity: 6, email: "buyer@example.com" },
             headers: { "Idempotency-Key" => "reservation-full-2" },
             as: :json
        assert_response :created

        post api_v1_reservations_path,
             params: { event_id: @event.id, quantity: 6, email: "buyer@example.com" },
             headers: { "Idempotency-Key" => "reservation-full-3" },
             as: :json

        assert_response :conflict
        assert_equal 0, @event.reservations.where(idempotency_key: "reservation-full-3").count
      end

      test "ignores client-supplied seat coordinates and allocates from the event layout" do
        post api_v1_reservations_path,
             params: {
               event_id: @event.id,
               quantity: 2,
               email: "buyer@example.com",
               row_id: 29,
               seat_start: 5,
               seat_end: 6
             },
             headers: { "Idempotency-Key" => "reservation-server-allocation-1" },
             as: :json

        assert_response :created
        assert_equal 17, response.parsed_body.fetch("row_id")
        assert_equal 1, response.parsed_body.fetch("seat_start")
        assert_equal 2, response.parsed_body.fetch("seat_end")
      end


      test "destroy cancels a held reservation and returns a successful response" do
        reservation = @event.reservations.create!(
          customer: customers(:one), row_id: 17, seat_range: 1...2, status: :held, hold_expires_at: 5.minutes.from_now
        )

        delete api_v1_reservation_path(reservation)

        assert_response :success
        assert_equal "cancelled", response.parsed_body.fetch("status")
        assert reservation.reload.cancelled?
      end
    end
  end
end
