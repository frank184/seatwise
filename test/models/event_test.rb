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
  end

  test "accepts a populated event" do
    assert_predicate events(:one), :valid?
  end
end
