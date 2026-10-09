# frozen_string_literal: true

module RedmineOidc
  # Normalizes the admin settings form payload.
  #
  # Extracted from the controller so the merge rules (blank secret handling,
  # array coercion, ignoring unpermitted keys) are unit-testable and shared
  # between the controller and any future API surface.
  module SettingsForm
    # Keys the settings form is allowed to write.
    PERMITTED = %w[
      enabled issuer client_id client_secret redirect_uri scopes button_label
      auto_create_user update_user_attributes admin_group auto_redirect
      hide_local_login end_session_enabled verify_ssl timeout default_role_ids
    ].freeze

    module_function

    # @param submitted [Hash, ActionController::Parameters] raw form payload
    # @return [Hash] settings ready to merge over the current values
    def normalize(submitted)
      data = submitted.respond_to?(:to_h) ? submitted.to_h.stringify_keys : {}
      allowed = data.slice(*PERMITTED)

      # An empty secret field means "keep the stored one" — never wipe it.
      allowed.delete('client_secret') if allowed['client_secret'].to_s.strip.blank?

      if allowed.key?('default_role_ids')
        allowed['default_role_ids'] = Array(allowed['default_role_ids']).reject { |id| id.to_s.strip.blank? }
      end

      allowed
    end

    # Merges a submitted payload over the current settings.
    def merge(submitted, current = Settings.current)
      current.merge(normalize(submitted))
    end
  end
end
