# Deterministic development data. Natural-key upserts keep reruns safe and
# update the sample schedule without removing records created by a developer.
return unless Rails.env.development?

venue_specs = [
  {
    name: "Grand Hall",
    rows: [
      { row_id: 1, label: "A", allocation_order: 1, seat_count: 12 },
      { row_id: 2, label: "B", allocation_order: 2, seat_count: 12 },
      { row_id: 3, label: "C", allocation_order: 3, seat_count: 10 }
    ]
  },
  {
    name: "Studio Theatre",
    rows: [
      { row_id: 1, label: "A", allocation_order: 1, seat_count: 10 },
      { row_id: 2, label: "B", allocation_order: 2, seat_count: 10 }
    ]
  },
  {
    name: "Riverside Stage",
    rows: [
      { row_id: 1, label: "Front", allocation_order: 1, seat_count: 8 },
      { row_id: 2, label: "Rear", allocation_order: 2, seat_count: 12 }
    ]
  }
]

venues = venue_specs.to_h do |spec|
  venue = Venue.find_or_initialize_by(name: spec[:name])
  venue.update!(layout: { rows: spec[:rows] })
  [spec[:name], venue]
end

customer_specs = %w[one@example.test two@example.test three@example.test]
customers = customer_specs.to_h do |email|
  customer = Customer.find_or_initialize_by(email: email)
  customer.update!(email_verified_at: Time.zone.parse("2026-11-01 12:00:00"), sign_in_code_attempts: 0)
  [email, customer]
end

event_specs = [
  { name: "Friday Evening Show", venue: "Grand Hall", starts_at: "2026-11-13 20:00", ends_at: "2026-11-13 22:00" },
  { name: "Saturday Matinee", venue: "Studio Theatre", starts_at: "2026-11-14 14:00", ends_at: "2026-11-14 16:00" },
  { name: "Indie Folk Night", venue: "Riverside Stage", starts_at: "2026-11-20 19:30", ends_at: "2026-11-20 21:30" },
  { name: "Sunday Jazz Brunch", venue: "Grand Hall", starts_at: "2026-11-22 11:00", ends_at: "2026-11-22 13:00" },
  { name: "Autumn Strings: Encore", venue: "Studio Theatre", starts_at: "2026-11-01 18:00", ends_at: "2026-11-01 20:00" },
  { name: "Late Summer Piano Recital", venue: "Grand Hall", starts_at: "2026-09-12 19:00", ends_at: "2026-09-12 21:00" },
  { name: "Riverside Comedy Hour", venue: "Riverside Stage", starts_at: "2026-10-24 20:00", ends_at: "2026-10-24 22:00" },
  { name: "Sunday Chamber Ensemble", venue: "Studio Theatre", starts_at: "2026-11-08 15:00", ends_at: "2026-11-08 17:00" },
  { name: "The Paper Moons", venue: "Riverside Stage", starts_at: "2026-11-27 20:00", ends_at: "2026-11-27 22:00" },
  { name: "Winter Lights Orchestra", venue: "Grand Hall", starts_at: "2026-12-04 19:30", ends_at: "2026-12-04 21:30" },
  { name: "Studio Stories: Improv", venue: "Studio Theatre", starts_at: "2026-12-06 19:00", ends_at: "2026-12-06 21:00" },
  { name: "New Year Folk Session", venue: "Riverside Stage", starts_at: "2027-01-09 19:00", ends_at: "2027-01-09 21:00" },
  { name: "Grand Hall Film Scores", venue: "Grand Hall", starts_at: "2027-01-16 20:00", ends_at: "2027-01-16 22:00" },
  { name: "Studio Matinee: The Seagull", venue: "Studio Theatre", starts_at: "2027-01-23 14:00", ends_at: "2027-01-23 16:30" },
  { name: "Riverside Winter Jazz", venue: "Riverside Stage", starts_at: "2027-02-05 20:00", ends_at: "2027-02-05 22:00" },
  { name: "Valentine Strings", venue: "Grand Hall", starts_at: "2027-02-14 19:00", ends_at: "2027-02-14 21:00" },
  { name: "Spring Preview: New Voices", venue: "Studio Theatre", starts_at: "2027-03-06 19:30", ends_at: "2027-03-06 21:30" }
]

events = event_specs.to_h do |spec|
  venue = venues.fetch(spec[:venue])
  event = Event.find_or_initialize_by(name: spec[:name], venue: venue)
  event.update!(
    start_time: Time.zone.parse(spec[:starts_at]),
    end_time: Time.zone.parse(spec[:ends_at]),
    layout_snapshot: venue.layout
  )
  [spec[:name], event]
end

reservation_specs = [
  { event: "Friday Evening Show", customer: "one@example.test", row_id: 1, seats: 1...2, status: :held, expires_at: "2026-11-13 19:45" },
  { event: "Saturday Matinee", customer: "two@example.test", row_id: 1, seats: 1...2, status: :confirmed },
  { event: "Indie Folk Night", customer: "three@example.test", row_id: 2, seats: 4...7, status: :confirmed }
]

reservation_specs.each do |spec|
  event = events.fetch(spec[:event])
  reservation = Reservation.find_or_initialize_by(
    event: event,
    customer: customers.fetch(spec[:customer]),
    row_id: spec[:row_id],
    seat_range: spec[:seats]
  )
  reservation.update!(status: spec[:status], hold_expires_at: spec[:expires_at] && Time.zone.parse(spec[:expires_at]))
end

puts "Seeded #{events.size} sample events across #{venues.size} venues."
