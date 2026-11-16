Rails.application.config.session_store :cookie_store,
                                       key: "_seatwise_session",
                                       expire_after: 30.days,
                                       httponly: true,
                                       same_site: :lax,
                                       secure: Rails.env.production?
