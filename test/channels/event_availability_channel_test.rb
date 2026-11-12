require "test_helper"

class EventAvailabilityChannelTest < ActionCable::Channel::TestCase
  test "subscribes to the requested event availability stream" do
    event = events(:one)

    subscribe event_id: event.id

    assert subscription.confirmed?
    assert_has_stream "event_availability:#{event.id}"
  end

  test "rejects a missing event id" do
    subscribe

    assert_predicate subscription, :rejected?
  end

  test "rejects an unknown event id" do
    subscribe event_id: -1

    assert_predicate subscription, :rejected?
  end
end
