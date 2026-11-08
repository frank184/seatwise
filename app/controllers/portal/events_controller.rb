module Portal
  class EventsController < ApplicationController
    layout "portal"

    def index
    end

    def show
      @event_id = params[:id]
    end
  end
end
