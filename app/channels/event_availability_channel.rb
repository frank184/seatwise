class EventAvailabilityChannel < ApplicationCable::Channel
  def subscribed
    event = Event.find_by(id: params[:event_id])
    return reject unless event

    stream_from "event_availability:#{event.id}"
  end
end
