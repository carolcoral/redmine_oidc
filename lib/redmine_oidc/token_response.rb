# frozen_string_literal: true

module RedmineOidc
  # Value object wrapping a successful token endpoint response.
  class TokenResponse
    attr_reader :raw

    def initialize(raw)
      @raw = raw.is_a?(Hash) ? raw : {}
    end

    def id_token
      raw['id_token']
    end

    def access_token
      raw['access_token']
    end

    def refresh_token
      raw['refresh_token']
    end

    def token_type
      raw['token_type'] || 'Bearer'
    end

    def expires_in
      raw['expires_in'].to_i
    end

    def scope
      raw['scope']
    end
  end
end
