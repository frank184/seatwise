require "test_helper"

module Api
  module V1
    class EventsControllerTest < ActionDispatch::IntegrationTest
      include ActiveSupport::Testing::TimeHelpers

      setup { travel_to Time.zone.local(2026, 11, 7, 12) }

      teardown { travel_back }

      test "index returns the versioned event shape in soonest-first order" do
        get api_v1_events_path

        assert_response :success
        body = response.parsed_body
        assert_equal "v1", body.dig("meta", "api_version")
        assert_equal 5, body.dig("meta", "total_count")
        assert_equal 5, body.dig("meta", "count")
        assert_equal "Autumn Strings: Encore", body.dig("data", 0, "name")
        assert_equal %w[
                       id
                       name
                       ticket_price_cents
                       starts_at
                       ends_at
                       past
                       venue
                       rows
                       seat_count
                       reserved_count
                       available_count
                     ].sort,
                     body.dig("data", 0).keys.sort
        assert_equal 1_000, body.dig("data", 0, "ticket_price_cents")
      end

      test "index filters upcoming and past events around the current time" do
        event_at_now =
          Event.create!(
            venue: venues(:one),
            name: "At the boundary",
            start_time: Time.current,
            end_time: 1.hour.from_now,
            ticket_price_cents: 1_000,
            layout_snapshot: venues(:one).layout
          )

        get api_v1_events_path, params: { when: "upcoming" }
        upcoming = response.parsed_body.fetch("data")
        assert_includes upcoming.map { |event| event.fetch("id") }, event_at_now.id
        assert upcoming.all? { |event| event.fetch("past") == false }

        get api_v1_events_path, params: { when: "past" }
        past = response.parsed_body.fetch("data")
        assert_equal [events(:past_encore).id], past.map { |event| event.fetch("id") }
        assert past.all? { |event| event.fetch("past") }
      end

      test "index searches event and venue names" do
        Event.create!(
          venue: venues(:one),
          name: "Riverside Comedy Hour",
          start_time: Time.zone.local(2026, 11, 24, 20),
          end_time: Time.zone.local(2026, 11, 24, 22),
          ticket_price_cents: 1_000,
          layout_snapshot: venues(:one).layout
        )

        get api_v1_events_path, params: { q: { name_or_venue_name_cont: "Riverside" } }

        assert_response :success
        assert_equal ["Indie Folk Night", "Riverside Comedy Hour"],
                     response.parsed_body.fetch("data").map { |event| event.fetch("name") }
      end

      test "index accepts a plain text search" do
        get api_v1_events_path, params: { q: "Folk" }

        assert_response :success
        assert_equal ["Indie Folk Night"],
                     response.parsed_body.fetch("data").map { |event| event.fetch("name") }
      end

      test "index ignores unsupported search attributes" do
        get api_v1_events_path,
            params: {
              q: {
                name_or_venue_name_cont: "Folk",
                created_at_eq: "not permitted"
              }
            }

        assert_response :success
        assert_equal ["Indie Folk Night"],
                     response.parsed_body.fetch("data").map { |event| event.fetch("name") }
      end

      test "index sorts latest and by name, and falls back for unknown sort values" do
        get api_v1_events_path, params: { sort: "latest" }
        assert_equal "Sunday Jazz Brunch", response.parsed_body.dig("data", 0, "name")

        get api_v1_events_path, params: { sort: "name" }
        assert_equal "Autumn Strings: Encore", response.parsed_body.dig("data", 0, "name")

        get api_v1_events_path, params: { sort: "unsupported" }
        assert_equal "Autumn Strings: Encore", response.parsed_body.dig("data", 0, "name")
      end

      test "index paginates results and reports navigation metadata" do
        7.times do |index|
          Event.create!(
            venue: venues(:one),
            name: "Pagination case #{index + 1}",
            start_time: Time.current + (index + 1).days,
            end_time: Time.current + (index + 1).days + 1.hour,
            ticket_price_cents: 1_000,
            layout_snapshot: venues(:one).layout
          )
        end

        get api_v1_events_path, params: { q: { name_cont: "Pagination case" }, page: 1 }
        first_page = response.parsed_body
        assert_equal 7, first_page.dig("meta", "total_count")
        assert_equal 6, first_page.dig("meta", "per_page")
        assert_equal 6, first_page.dig("meta", "count")
        assert_equal 2, first_page.dig("meta", "total_pages")
        assert_equal 2, first_page.dig("meta", "next_page")
        assert_nil first_page.dig("meta", "previous_page")

        get api_v1_events_path, params: { q: { name_cont: "Pagination case" }, page: 2 }
        second_page = response.parsed_body
        assert_equal 2, second_page.dig("meta", "page")
        assert_equal 1, second_page.dig("meta", "count")
        assert_equal 1, second_page.dig("data").length
        assert_nil second_page.dig("meta", "next_page")
        assert_equal 1, second_page.dig("meta", "previous_page")
      end

      test "show returns venue, row availability, and active reservation seats" do
        event = events(:one)
        Reservation.create!(
          event: event,
          customer: customers(:two),
          row_id: 2,
          seat_range: 1...3,
          status: :confirmed
        )
        Reservation.create!(
          event: event,
          customer: customers(:three),
          row_id: 1,
          seat_range: 2...3,
          status: :held,
          hold_expires_at: 1.minute.ago
        )
        Reservation.create!(
          event: event,
          customer: customers(:three),
          row_id: 1,
          seat_range: 3...4,
          status: :cancelled
        )

        get api_v1_event_path(event)

        assert_response :success
        body = response.parsed_body
        assert_equal "v1", body.dig("meta", "api_version")
        assert_equal event.venue.name, body.dig("data", "venue", "name")
        assert_equal [1], body.dig("data", "rows", 0, "reserved_seats")
        assert_equal [1, 2], body.dig("data", "rows", 1, "reserved_seats")
        assert_equal 3, body.dig("data", "reserved_count")
        assert_equal 127, body.dig("data", "available_count")
      end

      test "show returns not found for an unknown event" do
        get api_v1_event_path(id: "missing")

        assert_response :not_found
      end
    end
  end
end
