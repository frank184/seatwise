require "test_helper"

module Api
  module V1
    class PrivateReservationsControllerTest < ActionDispatch::IntegrationTest
      include ActiveSupport::Testing::TimeHelpers

      setup do
        travel_to Time.zone.local(2026, 11, 9, 12)
        @client =
          Doorkeeper::Application.create!(
            name: "Private reservation API client",
            redirect_uri: "https://client.example.test/callback",
            scopes: "reservations:read reservations:manage",
            confidential: false,
            secret: nil
          )
        @event = create_event
        @owned_reservation = create_reservation(customer: customers(:one))
        @other_reservation = create_reservation(customer: customers(:two), row_id: 2)
      end

      teardown { travel_back }

      test "private list and detail require a valid customer bearer token" do
        get api_v1_reservations_path
        assert_response :unauthorized

        access_token = token_for(customers(:one), scopes: "reservations:read")
        access_token.update!(created_at: 16.minutes.ago)
        get api_v1_reservations_path, headers: bearer(access_token)
        assert_response :unauthorized

        access_token = token_for(customers(:one), scopes: "reservations:read")
        access_token.revoke
        get api_v1_reservations_path, headers: bearer(access_token)
        assert_response :unauthorized
      end

      test "a valid token with a non-Customer owner is unauthorized" do
        non_customer_owner = @client.dup
        non_customer_owner.name = "Non-customer OAuth owner"
        non_customer_owner.uid = SecureRandom.urlsafe_base64(32)
        non_customer_owner.save!
        access_token = token_for(non_customer_owner, scopes: "reservations:read")

        get api_v1_reservations_path, headers: bearer(access_token)

        assert_response :unauthorized
      end

      test "list and detail are scoped through the authenticated customer" do
        access_token = token_for(customers(:one), scopes: "reservations:read")

        get api_v1_reservations_path, headers: bearer(access_token)

        assert_response :success
        assert_equal customers(:one).reservations.order(created_at: :desc).pluck(:id),
                     response.parsed_body.fetch("data").map { |item| item.fetch("id") }
        assert_equal customers(:one).reservations.count,
                     response.parsed_body.dig("meta", "total_count")
        owned_payload =
          response
            .parsed_body
            .fetch("data")
            .find { |item| item.fetch("id") == @owned_reservation.id }
        assert_equal "Private reservation API test", owned_payload.dig("event", "name")
        assert_equal "no-store", response.headers["Cache-Control"]

        get api_v1_reservation_path(@owned_reservation), headers: bearer(access_token)
        assert_response :success
        assert_equal @owned_reservation.id, response.parsed_body.fetch("id")

        get api_v1_reservation_path(@other_reservation), headers: bearer(access_token)

        assert_response :not_found
        assert_equal "held", @other_reservation.reload.status
      end

      test "reservation listing supports status and search filters with paginated metadata" do
        access_token = token_for(customers(:one), scopes: "reservations:read")
        11.times { |index| create_reservation(customer: customers(:one), row_id: index + 10) }

        get api_v1_reservations_path,
            params: {
              status: "active",
              q: "Private reservation",
              page: 2
            },
            headers: bearer(access_token)

        assert_response :success
        body = response.parsed_body
        assert_equal 2, body.dig("meta", "page")
        assert_equal 10, body.dig("meta", "per_page")
        assert_equal 12, body.dig("meta", "total_count")
        assert_equal 2, body.dig("meta", "total_pages")
        assert_equal 2, body.fetch("data").length

        get api_v1_reservations_path,
            params: {
              status: "active",
              q: "Private reservation",
              page: 99
            },
            headers: bearer(access_token)

        assert_response :success
        assert_equal 2, response.parsed_body.dig("meta", "page")
        assert_equal 2, response.parsed_body.fetch("data").length

        get api_v1_reservations_path, params: { status: "history" }, headers: bearer(access_token)

        assert_response :success
        assert_empty response.parsed_body.fetch("data")
        assert_equal 0, response.parsed_body.dig("meta", "total_count")
      end

      test "reservation listing expires elapsed holds and filters by status and venue" do
        access_token = token_for(customers(:one), scopes: "reservations:read")
        expired_reservation = @owned_reservation
        expired_reservation.update!(hold_expires_at: 1.second.ago)
        other_venue_event =
          Event.create!(
            venue: venues(:two),
            name: "Other venue reservation",
            start_time: 1.day.from_now,
            end_time: 1.day.from_now + 2.hours,
            ticket_price_cents: 1_000,
            layout_snapshot: {
              "rows" => [{ "row_id" => 1, "seat_count" => 20 }]
            }
          )
        other_venue_reservation =
          Reservation.create!(
            event: other_venue_event,
            customer: customers(:one),
            row_id: 1,
            seat_range: 1...2,
            status: :held,
            hold_expires_at: 5.minutes.from_now
          )

        get api_v1_reservations_path,
            params: {
              status: "expired",
              venue_id: venues(:one).id
            },
            headers: bearer(access_token)

        assert_response :success
        assert expired_reservation.reload.expired?
        body = response.parsed_body
        assert_equal [expired_reservation.id], body.fetch("data").map { |item| item.fetch("id") }
        assert_includes body.dig("meta", "venues").map { |venue| venue.fetch("id") },
                        venues(:two).id

        get api_v1_reservations_path,
            params: {
              status: "held",
              venue_id: venues(:two).id
            },
            headers: bearer(access_token)

        assert_response :success
        assert_equal [other_venue_reservation.id],
                     response.parsed_body.fetch("data").map { |item| item.fetch("id") }
      end

      test "private reads require reservations read scope" do
        access_token = token_for(customers(:one), scopes: "reservations:manage")

        get api_v1_reservations_path, headers: bearer(access_token)

        assert_response :forbidden
      end

      test "customer reservation creation binds to the token owner and requires manage scope" do
        access_token = token_for(customers(:one), scopes: "reservations:manage")
        params = {
          event_id: @event.id,
          quantity: 1,
          email: customers(:one).email,
          customer_id: customers(:two).id
        }
        existing_reservations_count = @event.reservations.count

        post api_v1_reservations_path,
             params:,
             headers: bearer(access_token).merge("Idempotency-Key" => "customer-create-owner-1"),
             as: :json

        assert_response :unprocessable_entity
        assert_equal existing_reservations_count, @event.reservations.count

        params[:customer_id] = customers(:one).id
        params[:email] = customers(:two).email
        post api_v1_reservations_path,
             params:,
             headers: bearer(access_token).merge("Idempotency-Key" => "customer-create-email-1"),
             as: :json

        assert_response :unprocessable_entity
        assert_equal existing_reservations_count, @event.reservations.count

        params[:email] = customers(:one).email
        post api_v1_reservations_path,
             params:,
             headers: bearer(access_token).merge("Idempotency-Key" => "customer-create-success-1"),
             as: :json

        assert_response :created
        assert_equal customers(:one), Reservation.find(response.parsed_body.fetch("id")).customer
        assert_nil Reservation.find(response.parsed_body.fetch("id")).guest
        assert_equal existing_reservations_count + 1, @event.reservations.count
      end

      test "customer reservation creation requires manage scope" do
        access_token = token_for(customers(:one), scopes: "reservations:read")
        existing_reservations_count = @event.reservations.count

        post api_v1_reservations_path,
             params: {
               event_id: @event.id,
               quantity: 1,
               email: customers(:one).email
             },
             headers:
               bearer(access_token).merge("Idempotency-Key" => "customer-create-no-manage-1"),
             as: :json

        assert_response :forbidden
        assert_equal existing_reservations_count, @event.reservations.count
      end

      test "guest email matching an existing customer does not grant access to that customer's reservations" do
        post api_v1_guest_sessions_path, params: {}, as: :json
        guest_secret = response.parsed_body.fetch("guest_token")
        post api_v1_reservations_path,
             params: {
               event_id: @event.id,
               quantity: 1,
               email: customers(:one).email
             },
             headers: {
               "Authorization" => "Guest #{guest_secret}",
               "Idempotency-Key" => "guest-existing-customer-email-1"
             },
             as: :json
        assert_response :created
        guest_reservation = Reservation.find(response.parsed_body.fetch("id"))
        assert_equal customers(:one), guest_reservation.customer
        assert_not_equal @owned_reservation.guest_id, guest_reservation.guest_id

        delete api_v1_reservation_path(@owned_reservation),
               headers: {
                 "Authorization" => "Guest #{guest_secret}"
               }

        assert_response :not_found
        assert @owned_reservation.reload.held?
      end

      test "customer cancellation requires manage scope and never exposes another customer's hold" do
        read_token = token_for(customers(:one), scopes: "reservations:read")
        delete api_v1_reservation_path(@owned_reservation), headers: bearer(read_token)
        assert_response :forbidden
        assert @owned_reservation.reload.held?

        manage_token = token_for(customers(:one), scopes: "reservations:manage")
        delete api_v1_reservation_path(@other_reservation), headers: bearer(manage_token)
        assert_response :not_found
        assert @other_reservation.reload.held?

        delete api_v1_reservation_path(@owned_reservation), headers: bearer(manage_token)
        assert_response :success
        assert @owned_reservation.reload.cancelled?
      end

      private

      def create_event
        Event.create!(
          venue: venues(:one),
          name: "Private reservation API test",
          start_time: 1.day.from_now,
          end_time: 1.day.from_now + 2.hours,
          ticket_price_cents: 1_000,
          layout_snapshot: {
            "rows" => [{ "row_id" => 1, "seat_count" => 20 }]
          }
        )
      end

      def create_reservation(customer:, row_id: 1)
        Reservation.create!(
          event: @event,
          customer:,
          row_id:,
          seat_range: (row_id * 10)...(row_id * 10 + 1),
          status: :held,
          hold_expires_at: 5.minutes.from_now
        )
      end

      def token_for(owner, scopes:)
        Doorkeeper::AccessToken.create!(
          application: @client,
          resource_owner: owner,
          scopes:,
          expires_in: 15.minutes.to_i
        )
      end

      def bearer(token)
        { "Authorization" => "Bearer #{token.plaintext_token}" }
      end
    end
  end
end
