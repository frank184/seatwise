# Deterministic development data. Natural-key upserts keep reruns safe and
# update the sample schedule without removing records created by a developer.
return unless Rails.env.development?

seed_reference_date = Time.zone.today
seed_reference_time =
  Time.zone.local(seed_reference_date.year, seed_reference_date.month, seed_reference_date.day, 12)
persist_seed_record =
  lambda do |record, attributes|
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

venues =
  venue_specs.to_h do |spec|
    venue = Venue.find_or_initialize_by(name: spec[:name])
    persist_seed_record.call(venue, layout: { rows: spec[:rows] })
    [spec[:name], venue]
  end

customer_specs =
  %w[one@example.test two@example.test three@example.test] +
    (1..32).map { |number| "guest#{number.to_s.rjust(2, "0")}@seatwise.test" }
customers =
  customer_specs.to_h do |email|
    customer = Customer.find_or_initialize_by(email: email)
    persist_seed_record.call(
      customer,
      email_verified_at: seed_reference_time - 1.day,
      sign_in_code_attempts: 0
    )
    [email, customer]
  end

event_specs = [
  {
    name: "Friday Evening Show",
    venue: "Grand Hall",
    days_from_reference: 6,
    start_hour: 20,
    duration_minutes: 120
  },
  {
    name: "Saturday Matinee",
    venue: "Studio Theatre",
    days_from_reference: 7,
    start_hour: 14,
    duration_minutes: 120
  },
  {
    name: "Indie Folk Night",
    venue: "Riverside Stage",
    days_from_reference: 13,
    start_hour: 19,
    start_minute: 30,
    duration_minutes: 120
  },
  {
    name: "Sunday Jazz Brunch",
    venue: "Grand Hall",
    days_from_reference: 15,
    start_hour: 11,
    duration_minutes: 120
  },
  {
    name: "Autumn Strings: Encore",
    venue: "Studio Theatre",
    days_from_reference: -6,
    start_hour: 18,
    duration_minutes: 120
  },
  {
    name: "Late Summer Piano Recital",
    venue: "Grand Hall",
    days_from_reference: -56,
    start_hour: 19,
    duration_minutes: 120
  },
  {
    name: "Riverside Comedy Hour",
    venue: "Riverside Stage",
    days_from_reference: -14,
    start_hour: 20,
    duration_minutes: 120
  },
  {
    name: "Sunday Chamber Ensemble",
    venue: "Studio Theatre",
    days_from_reference: 1,
    start_hour: 15,
    duration_minutes: 120
  },
  {
    name: "The Paper Moons",
    venue: "Riverside Stage",
    days_from_reference: 20,
    start_hour: 20,
    duration_minutes: 120
  },
  {
    name: "Winter Lights Orchestra",
    venue: "Grand Hall",
    days_from_reference: 27,
    start_hour: 19,
    start_minute: 30,
    duration_minutes: 120
  },
  {
    name: "Studio Stories: Improv",
    venue: "Studio Theatre",
    days_from_reference: 29,
    start_hour: 19,
    duration_minutes: 120
  },
  {
    name: "New Year Folk Session",
    venue: "Riverside Stage",
    days_from_reference: 63,
    start_hour: 19,
    duration_minutes: 120
  },
  {
    name: "Grand Hall Film Scores",
    venue: "Grand Hall",
    days_from_reference: 70,
    start_hour: 20,
    duration_minutes: 120
  },
  {
    name: "Studio Matinee: The Seagull",
    venue: "Studio Theatre",
    days_from_reference: 77,
    start_hour: 14,
    duration_minutes: 150
  },
  {
    name: "Riverside Winter Jazz",
    venue: "Riverside Stage",
    days_from_reference: 90,
    start_hour: 20,
    duration_minutes: 120
  },
  {
    name: "Valentine Strings",
    venue: "Grand Hall",
    days_from_reference: 99,
    start_hour: 19,
    duration_minutes: 120
  },
  {
    name: "Spring Preview: New Voices",
    venue: "Studio Theatre",
    days_from_reference: 119,
    start_hour: 19,
    start_minute: 30,
    duration_minutes: 120
  }
]

events =
  event_specs.to_h do |spec|
    venue = venues.fetch(spec[:venue])
    event = Event.find_or_initialize_by(name: spec[:name], venue: venue)
    start_time =
      (seed_reference_time + spec.fetch(:days_from_reference).days).change(
        hour: spec.fetch(:start_hour),
        min: spec.fetch(:start_minute, 0),
        sec: 0
      )
    persist_seed_record.call(
      event,
      start_time: start_time,
      end_time: start_time + spec.fetch(:duration_minutes).minutes,
      ticket_price_cents: spec.fetch(:ticket_price_cents, 1_000),
      layout_snapshot: venue.layout
    )
    [spec[:name], event]
  end

reservation_specs = [
  {
    event: "Friday Evening Show",
    customer: "one@example.test",
    row_id: 1,
    seats: 1...2,
    status: :held
  },
  {
    event: "Saturday Matinee",
    customer: "two@example.test",
    row_id: 1,
    seats: 1...2,
    status: :confirmed
  },
  {
    event: "Indie Folk Night",
    customer: "three@example.test",
    row_id: 2,
    seats: 4...7,
    status: :confirmed
  }
]

reservation_specs.each do |spec|
  event = events.fetch(spec[:event])
  reservation =
    Reservation.find_or_initialize_by(
      event: event,
      customer: customers.fetch(spec[:customer]),
      row_id: spec[:row_id],
      seat_range: spec[:seats]
    )
  persist_seed_record.call(
    reservation,
    status: spec[:status],
    hold_expires_at: spec[:status] == :held ? event.start_time - 15.minutes : nil
  )
end

# Keep the original sample reservations, and build a repeatable activity stream
# around them. Existing reservations, including prior seeded activity, occupy
# their seats so a rerun never tries to recreate overlapping inventory.
simulation_customers =
  customer_specs.grep(/@seatwise\.test\z/).map { |email| customers.fetch(email) }
simulation_customer_ids = simulation_customers.map(&:id)
payment_rng = Random.new(20_261_107)
reservation_rng = Random.new(20_261_107)
simulated_reservations = []

events.each_value.with_index do |event, event_index|
  event_rng = Random.new(20_261_107 + event_index)
  rows = event.layout_snapshot.fetch("rows")
  occupied = rows.to_h { |row| [row.fetch("row_id"), []] }

  event
    .reservations
    .includes(:customer)
    .each do |reservation|
      simulated_reservation = simulation_customer_ids.include?(reservation.customer_id)
      next unless simulated_reservation || reservation.held? || reservation.confirmed?

      occupied.fetch(reservation.row_id) << reservation.seat_range
    end

  capacity = rows.sum { |row| row.fetch("seat_count") }
  target_count = event_rng.rand(9..[capacity / 5, 18].min)
  existing_simulated_count = event.reservations.where(customer_id: simulation_customer_ids).count
  missing_count = [target_count - existing_simulated_count, 0].max
  generated = []
  attempts = 0

  while generated.size < missing_count && attempts < missing_count * 80
    attempts += 1
    row = rows.sample(random: event_rng)
    first_seat = event_rng.rand(1..row.fetch("seat_count"))
    group_size = event_rng.rand(1..[4, row.fetch("seat_count") - first_seat + 1].min)
    seats = first_seat...(first_seat + group_size)
    next if occupied.fetch(row.fetch("row_id")).any? { |range| range.overlaps?(seats) }

    occupied.fetch(row.fetch("row_id")) << seats
    generated << { row_id: row.fetch("row_id"), seats: seats, group_size: group_size }
  end

  customers_for_event = simulation_customers.shuffle(random: event_rng)
  generated.each_with_index do |booking, index|
    customer = customers_for_event[index % customers_for_event.size]
    reservation =
      Reservation.find_or_initialize_by(
        event: event,
        customer: customer,
        row_id: booking.fetch(:row_id),
        seat_range: booking.fetch(:seats)
      )
    persist_seed_record.call(
      reservation,
      status: :confirmed,
      hold_expires_at: nil,
      created_at: seed_reference_time
    )
    simulated_reservations << reservation
  end

  past_event = event.start_time < seed_reference_time
  statuses =
    if past_event
      %i[confirmed confirmed confirmed confirmed cancelled expired]
    else
      %i[confirmed confirmed confirmed held held cancelled expired]
    end
  event
    .reservations
    .where(customer_id: simulation_customer_ids)
    .to_a
    .sort_by do |reservation|
      [
        reservation.customer_id,
        reservation.row_id,
        reservation.seat_range.begin,
        reservation.seat_range.end
      ]
    end
    .each do |reservation|
      status = statuses.sample(random: reservation_rng)
      booked_at =
        if past_event
          event.start_time - reservation_rng.rand(1..28).days - reservation_rng.rand(1..18).hours
        else
          seed_reference_time - reservation_rng.rand(0..28).days - reservation_rng.rand(0..18).hours
        end
      persist_seed_record.call(
        reservation,
        status: status,
        hold_expires_at: status == :held ? event.start_time - 15.minutes : nil,
        created_at: booked_at
      )
    end
end

sample_customer_ids = customers.values.map(&:id)
Reservation
  .includes(:customer)
  .where(customer_id: sample_customer_ids)
  .find_each do |reservation|
    group_size = reservation.seat_range.size
    amount = group_size * payment_rng.rand(3_500..9_500)
    payment_statuses =
      if reservation.confirmed?
        %w[succeeded succeeded succeeded refunded]
      elsif reservation.held?
        ["pending"]
      elsif reservation.cancelled?
        %w[failed refunded]
      else
        ["failed", "failed", nil]
      end
    status = payment_statuses.sample(random: payment_rng)
    next unless status

    persist_seed_record.call(
      Payment.find_or_initialize_by(external_id: "seed-payment-#{reservation.id}"),
      reservation: reservation,
      status: status,
      amount: amount,
      provider_key: "simulator",
      currency: "cad"
    )

    if reservation.confirmed? && payment_rng.rand < 0.12
      persist_seed_record.call(
        Payment.find_or_initialize_by(external_id: "seed-retry-#{reservation.id}"),
        reservation: reservation,
        status: "failed",
        amount: amount,
        provider_key: "simulator",
        currency: "cad"
      )
    end
  end

puts "Seeded #{events.size} sample events across #{venues.size} venues with #{customers.size} customers and #{simulated_reservations.size} simulated reservations."

DevelopmentOauthClients.seed!.each do |application|
  puts "OAuth client #{application.name}: client_id=#{application.uid} callback=#{application.redirect_uri}"
end
