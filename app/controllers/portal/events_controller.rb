module Portal
  class EventsController < ApplicationController
    layout "portal"

    def index
      @venues = Venue.order(:name)
    end

    def show
      @event_id = params[:id]
    end
  end
end
