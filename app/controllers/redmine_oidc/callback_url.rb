# frozen_string_literal: true

module RedmineOidc
  # Builds the absolute callback URL the provider must be configured with.
  #
  # Redmine may be served behind a reverse proxy, so the URL is derived from the
  # request (honouring X-Forwarded-* when present) rather than from a hardcoded
  # setting. Overriding via `Setting.plugin_redmine_oidc['redirect_uri']` is
  # supported for deployments where the public URL cannot be inferred.
  module CallbackUrl
    module_function

    def build(request)
      override = RedmineOidc::Settings['redirect_uri'].to_s.strip
      return override if override.present?

      "#{request.base_url}/oidc/callback"
    end
  end
end
