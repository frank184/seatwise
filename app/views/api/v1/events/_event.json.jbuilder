json.id event.id
json.name event.name
json.starts_at event.start_time.iso8601
json.ends_at event.end_time.iso8601
json.past event.start_time < Time.current
json.venue do
  json.name event.venue.name
end
json.rows event.rows_with_availability
json.seat_count event.seat_count
json.reserved_count event.reserved_count
json.available_count event.available_count
