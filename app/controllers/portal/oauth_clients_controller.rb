module Portal
  class OauthClientsController < ApplicationController
    layout "portal"

    def start
      @client_id = portal_oauth_client.uid
      @redirect_uri = portal_callback_uri
      @return_to = safe_local_path(params[:return_to]) || account_reservations_path
    end

    def callback
      @client_id = portal_oauth_client.uid
      @redirect_uri = portal_callback_uri
      @code = params[:code].to_s
      @state = params[:state].to_s
      @oauth_error = params[:error].present?
    end

    def reservations
      @client_id = portal_oauth_client.uid
      @redirect_uri = portal_callback_uri
      @return_to = account_reservations_path
    end

    private

    def portal_oauth_client
      @portal_oauth_client ||= Doorkeeper::Application.find_by!(name: "Seatwise Portal")
    end

    def portal_callback_uri
      "#{Rails.application.config.x.portal_origin}/oauth/callback"
    end

    def safe_local_path(value)
      return unless value.is_a?(String) && value.start_with?("/")
      if value.start_with?("//", "/\\") || value.include?("\\") ||
           value.match?(/[\u0000-\u001f\u007f]/)
        return
      end

      uri = URI.parse(value)
      return unless uri.scheme.nil? && uri.host.nil? && uri.userinfo.nil?

      value
    rescue URI::InvalidURIError
      nil
    end
  end
end
