# frozen_string_literal: true

module RedmineOidc
  # View helpers shared by the plugin partials.
  module ViewHelper
    # Path to start the OIDC login flow.
    #
    # A blank back URL is omitted entirely so the generated link stays clean and
    # the controller falls back to the home page.
    def oidc_login_link(back_url = nil)
      back_url.present? ? oidc_login_path(back_url: back_url) : oidc_login_path
    end

    def oidc_button_label
      label = RedmineOidc::Settings['button_label'].to_s.strip
      label.presence || 'OIDC'
    end

    def oidc_provider_name
      RedmineOidc::Settings['issuer'].to_s.presence || 'OIDC'
    end
  end
end
