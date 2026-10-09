# frozen_string_literal: true

module RedmineOidc
  # Probes the configured provider and produces the payload the admin
  # "Test connection" button renders.
  #
  # Extracted from the settings controller so the reporting logic (which fields
  # are surfaced, how failures are shaped) is testable without HTTP stubs at the
  # controller layer.
  module Connectivity
    module_function

    # @param client [RedmineOidc::Client]
    # @param callback_url [String]
    # @return [Hash] success payload, or failure payload with :success => false
    def report(client: Client.new, callback_url: nil)
      metadata = client.discovery.metadata
      keys = client.jwks

      {
        success: true,
        issuer: metadata['issuer'],
        authorization_endpoint: metadata['authorization_endpoint'],
        token_endpoint: metadata['token_endpoint'],
        userinfo_endpoint: metadata['userinfo_endpoint'],
        end_session_endpoint: metadata['end_session_endpoint'],
        jwks_keys: Array(keys).size,
        issuer_matches: client.discovery.issuer_matches?,
        callback_url: callback_url
      }
    rescue Discovery::Error, Client::Error => e
      { success: false, message: e.message }
    end
  end
end
