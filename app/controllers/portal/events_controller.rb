module Portal
  class EventsController < ApplicationController
    layout "portal"

    def index
      @venues = Venue.order(:name)
    end

    def show
      @event_id = params[:id]
      @customer_email = Customer.find_by(id: session[:customer_id])&.email
    end
  end
end
