module Api
  module V1
    class EventsController < BaseController
      SORTS = {
        "soonest" => "start_time asc",
        "latest" => "start_time desc",
        "name" => "name asc"
      }.freeze
      PER_PAGE = 6

      def index
        search = Event.ransack(event_search_params)
        @events = search.result.includes(:venue, :active_reservations).order(:id).page(params[:page]).per(PER_PAGE)
        render :index, formats: [:json]
      end

      def show
        @event = Event.includes(:venue, :active_reservations).find(params[:id])
        render :show, formats: [:json]
      end

      private

      def event_search_params
        raw_query = params[:q]
        conditions = if raw_query.is_a?(ActionController::Parameters)
          raw_query.permit(:name_or_venue_name_cont, :name_cont, :venue_name_cont, :start_time_gteq, :start_time_lt).to_h
        elsif raw_query.present?
          { name_or_venue_name_cont: raw_query.to_s }
        else
          {}
        end

        conditions[:start_time_gteq] = Time.current if params[:when] == "upcoming"
        conditions[:start_time_lt] = Time.current if params[:when] == "past"
        conditions[:s] = SORTS.fetch(params[:sort], SORTS.fetch("soonest"))
        conditions
      end
    end
  end
end
