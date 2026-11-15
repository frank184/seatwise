require "application_system_test_case"

module Portal
  class EventsTest < ApplicationSystemTestCase
    setup do
      @event = events(:one)
      @event.update!(start_time: 2.hours.from_now, end_time: 4.hours.from_now)
    end

    test "event cards show relative start time alongside date and clock time" do
      visit root_path

      assert_selector "#events-list [data-event-relative-time]", text: /\AStarts in /
      assert_selector "#events-list [data-event-date]", text: /.+/
      assert_selector "#events-list [data-event-time]", text: /.+/
    end

    test "past event cards and details say when the event started" do
      @event.update!(start_time: 2.hours.ago, end_time: 1.hour.ago)

      visit root_path(when: "past")
      assert_selector "#events-list [data-event-relative-time]", text: /\AStarted .+ ago/

      visit event_path(@event)
      assert_selector "[data-detail-relative-time]", text: /\AStarted .+ ago/
      assert_selector "[data-detail-date]", text: /.+/
      assert_selector "[data-detail-start]", text: /.+/
    end

    test "event details show relative start time without replacing the calendar date" do
      visit event_path(@event)

      assert_selector "[data-detail-relative-time]", text: /\AStarts in /
      assert_selector "[data-detail-date]", text: /.+/
      assert_selector "[data-detail-start]", text: /.+/
      assert_selector "[data-detail-end]", text: /.+/
    end
  end
end
