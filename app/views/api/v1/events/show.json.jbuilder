json.data do
  json.partial! "api/v1/events/event", event: @event
end

json.meta do
  json.api_version "v1"
end
