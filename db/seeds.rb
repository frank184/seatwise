# Load the shared test dataset into a fresh development database.
require "active_record/fixtures"

if Rails.env.development?
  fixture_tables = [ Venue, Customer, Event, Reservation, Payment ]

  if fixture_tables.none?(&:exists?)
    ActiveRecord::FixtureSet.create_fixtures(
      Rails.root.join("test/fixtures"),
      %w[venues customers events reservations payments]
    )
  elsif fixture_tables.any?(&:exists?)
    puts "Skipping development fixtures because one or more seed tables already contain data."
  end
end
