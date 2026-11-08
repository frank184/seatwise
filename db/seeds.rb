# Deterministic development data. Natural-key upserts keep reruns safe and
# update the sample schedule without removing records created by a developer.
return unless Rails.env.development?

seed_reference_time = Time.zone.parse("2026-11-07 12:00")
persist_seed_record = lambda do |record, attributes|
  record.assign_attributes(attributes)
  record.save! if record.new_record? || record.has_changes_to_save?
  record
end

venue_specs = [
  {
    name: "Grand Hall",
    rows: [
      { row_id: 1, label: "A", allocation_order: 1, seat_count: 18 },
      { row_id: 2, label: "B", allocation_order: 2, seat_count: 18 },
      { row_id: 3, label: "C", allocation_order: 3, seat_count: 18 },
      { row_id: 4, label: "D", allocation_order: 4, seat_count: 18 },
      { row_id: 5, label: "E", allocation_order: 5, seat_count: 16 },
      { row_id: 6, label: "F", allocation_order: 6, seat_count: 16 },
      { row_id: 7, label: "G", allocation_order: 7, seat_count: 14 },
      { row_id: 8, label: "H", allocation_order: 8, seat_count: 12 }
    ]
  },
  {
    name: "Studio Theatre",
    rows: [
      { row_id: 1, label: "A", allocation_order: 1, seat_count: 14 },
      { row_id: 2, label: "B", allocation_order: 2, seat_count: 16 },
      { row_id: 3, label: "C", allocation_order: 3, seat_count: 16 },
      { row_id: 4, label: "D", allocation_order: 4, seat_count: 14 },
      { row_id: 5, label: "E", allocation_order: 5, seat_count: 12 },
      { row_id: 6, label: "F", allocation_order: 6, seat_count: 10 }
    ]
  },
  {
    name: "Riverside Stage",
    rows: [
      { row_id: 1, label: "Front", allocation_order: 1, seat_count: 12 },
      { row_id: 2, label: "Middle", allocation_order: 2, seat_count: 14 },
      { row_id: 3, label: "Rear", allocation_order: 3, seat_count: 14 },
      { row_id: 4, label: "Balcony Left", allocation_order: 4, seat_count: 10 },
      { row_id: 5, label: "Balcony Right", allocation_order: 5, seat_count: 10 }
    ]
  }
]

venues = venue_specs.to_h do |spec|
  venue = Venue.find_or_initialize_by(name: spec[:name])
  persist_seed_record.call(venue, layout: { rows: spec[:rows] })
  [spec[:name], venue]
end

customer_specs = %w[one@example.test two@example.test three@example.test] + (1..32).map do |number|
  "guest#{number.to_s.rjust(2, '0')}@seatwise.test"
end
customers = customer_specs.to_h do |email|
  customer = Customer.find_or_initialize_by(email: email)
  persist_seed_record.call(customer, email_verified_at: Time.zone.parse("2026-11-01 12:00:00"), sign_in_code_attempts: 0)
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
  persist_seed_record.call(event,
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
  persist_seed_record.call(
    reservation,
    status: spec[:status],
    hold_expires_at: spec[:expires_at] && Time.zone.parse(spec[:expires_at])
  )
end

# Keep the original sample reservations, and build a repeatable activity stream
# around them. Existing developer reservations still occupy their seats.
simulation_customers = customer_specs.grep(/@seatwise\.test\z/).map { |email| customers.fetch(email) }
simulation_customer_ids = simulation_customers.map(&:id)
rng = Random.new(20_261_107)
simulated_reservations = []

events.each_value do |event|
  rows = event.layout_snapshot.fetch("rows")
  occupied = rows.to_h { |row| [row.fetch("row_id"), []] }

  event.reservations.includes(:customer).each do |reservation|
    next if simulation_customer_ids.include?(reservation.customer_id)
    next unless reservation.held? || reservation.confirmed?

    occupied.fetch(reservation.row_id) << reservation.seat_range
  end

  capacity = rows.sum { |row| row.fetch("seat_count") }
  target_count = rng.rand(9..[capacity / 5, 18].min)
  generated = []
  attempts = 0

  while generated.size < target_count && attempts < target_count * 80
    attempts += 1
    row = rows.sample(random: rng)
    first_seat = rng.rand(1..row.fetch("seat_count"))
    group_size = rng.rand(1..[4, row.fetch("seat_count") - first_seat + 1].min)
    seats = first_seat...(first_seat + group_size)
    next if occupied.fetch(row.fetch("row_id")).any? { |range| range.overlaps?(seats) }

    occupied.fetch(row.fetch("row_id")) << seats
    generated << { row_id: row.fetch("row_id"), seats: seats, group_size: group_size }
  end

  customers_for_event = simulation_customers.shuffle(random: rng)
  generated.each_with_index do |booking, index|
    customer = customers_for_event[index % customers_for_event.size]
    past_event = event.start_time < seed_reference_time
    status = if past_event
      %i[confirmed confirmed confirmed confirmed cancelled expired].sample(random: rng)
    else
      %i[confirmed confirmed confirmed held held cancelled expired].sample(random: rng)
    end
    hold_expires_at = status == :held ? event.start_time - 15.minutes : nil
    booked_at = event.start_time - rng.rand(1..28).days - rng.rand(1..18).hours

    reservation = Reservation.find_or_initialize_by(
      event: event,
      customer: customer,
      row_id: booking.fetch(:row_id),
      seat_range: booking.fetch(:seats)
    )
    persist_seed_record.call(
      reservation,
      status: status,
      hold_expires_at: hold_expires_at,
      created_at: booked_at
    )
    simulated_reservations << reservation
  end
end

sample_customer_ids = customers.values.map(&:id)
Reservation.includes(:customer).where(customer_id: sample_customer_ids).find_each do |reservation|
  group_size = reservation.seat_range.size
  amount = group_size * rng.rand(3_500..9_500)
  payment_statuses = if reservation.confirmed?
    ["succeeded", "succeeded", "succeeded", "refunded"]
  elsif reservation.held?
    ["pending"]
  elsif reservation.cancelled?
    ["failed", "refunded"]
  else
    ["failed", "failed", nil]
  end
  status = payment_statuses.sample(random: rng)
  next unless status

  persist_seed_record.call(
    Payment.find_or_initialize_by(external_id: "seed-payment-#{reservation.id}"),
    reservation: reservation,
    status: status,
    amount: amount
  )

  if reservation.confirmed? && rng.rand < 0.12
    persist_seed_record.call(
      Payment.find_or_initialize_by(external_id: "seed-retry-#{reservation.id}"),
      reservation: reservation,
      status: "failed",
      amount: amount
    )
  end
end

puts "Seeded #{events.size} sample events across #{venues.size} venues with #{customers.size} customers and #{simulated_reservations.size} simulated reservations."
