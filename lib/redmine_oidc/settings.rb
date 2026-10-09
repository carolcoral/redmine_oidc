# frozen_string_literal: true

module RedmineOidc
  # Plugin settings helper: single source of truth for defaults and lookups.
  module Settings
    DEFAULTS = {
      'enabled' => '0',
      'issuer' => '',
      'client_id' => '',
      'client_secret' => '',
      'redirect_uri' => '',
      'scopes' => 'openid profile email',
      'button_label' => 'OIDC',
      'auto_create_user' => '1',
      'default_role_ids' => [],
      'admin_group' => '',
      'update_user_attributes' => '1',
      'auto_redirect' => '0',
      'hide_local_login' => '0',
      'end_session_enabled' => '1',
      'verify_ssl' => '1',
      'timeout' => '10'
    }.freeze

    class << self
      # Current settings merged over defaults, tolerating missing keys.
      def current
        stored = Setting.plugin_redmine_oidc
        stored = {} unless stored.is_a?(Hash)
        DEFAULTS.merge(stored)
      end

      def [](key)
        current[key.to_s]
      end

      def enabled?
        truthy?(self['enabled'])
      end

      # OIDC integration is advertised on the login page only when fully configured.
      def configured?
        enabled? && self['issuer'].to_s.strip.present? && self['client_id'].to_s.strip.present?
      end

      def auto_create_user?
        truthy?(self['auto_create_user'])
      end

      def update_user_attributes?
        truthy?(self['update_user_attributes'])
      end

      def auto_redirect?
        truthy?(self['auto_redirect'])
      end

      def hide_local_login?
        truthy?(self['hide_local_login'])
      end

      def end_session_enabled?
        truthy?(self['end_session_enabled'])
      end

      def verify_ssl?
        truthy?(self['verify_ssl'])
      end

      def timeout
        value = self['timeout'].to_i
        value.positive? ? value : 10
      end

      def scopes
        self['scopes'].to_s.split(/[\s,]+/).reject(&:blank?)
      end

      def default_role_ids
        Array(self['default_role_ids']).map(&:to_i).reject(&:zero?)
      end

      def truthy?(value)
        %w[1 true yes on].include?(value.to_s.downcase)
      end
    end
  end
end
