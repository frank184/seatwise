module Portal
  class EventsController < ApplicationController
    def index
    end

    def show
      @event_id = params[:id]
    end
  end
end
