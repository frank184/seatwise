require "test_helper"

class EventTest < ActiveSupport::TestCase
  test "requires a venue, name, times, and layout snapshot" do
    event = Event.new

    assert_not event.valid?
    assert_includes event.errors[:venue], "must exist"
    assert_includes event.errors[:name], "can't be blank"
    assert_includes event.errors[:start_time], "can't be blank"
    assert_includes event.errors[:end_time], "can't be blank"
    assert_includes event.errors[:layout_snapshot], "can't be blank"
    assert_includes event.errors[:ticket_price_cents], "is not a number"
  end

  test "accepts a populated event" do
    assert_predicate events(:one), :valid?
  end

  test "requires a positive integer ticket price" do
    event = events(:one)

    event.ticket_price_cents = 0
    assert_not event.valid?
    assert_includes event.errors[:ticket_price_cents], "must be greater than 0"

    event.ticket_price_cents = -1
    assert_not event.valid?
    assert_includes event.errors[:ticket_price_cents], "must be greater than 0"
  end
end
