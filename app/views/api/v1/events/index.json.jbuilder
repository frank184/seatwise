json.data @events do |event|
  json.partial! "api/v1/events/event", event: event
end

json.meta do
  json.count @events.size
  json.total_count @events.total_count
  json.page @events.current_page
  json.per_page @events.limit_value
  json.total_pages @events.total_pages
  json.next_page @events.next_page
  json.previous_page @events.prev_page
  json.api_version "v1"
end
