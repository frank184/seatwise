require "test_helper"

class VenueTest < ActiveSupport::TestCase
  test "requires a name and layout" do
    venue = Venue.new

    assert_not venue.valid?
    assert_includes venue.errors[:name], "can't be blank"
    assert_includes venue.errors[:layout], "can't be blank"
  end

  test "accepts a populated venue" do
    assert_predicate venues(:one), :valid?
  end
end
