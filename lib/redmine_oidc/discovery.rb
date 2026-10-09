# frozen_string_literal: true

require 'json'
require 'uri'
require 'net/http'

module RedmineOidc
  # Fetches and caches the provider metadata document (RFC 8414 / OIDC Discovery).
  #
  # Discovery is intentionally performed against the configured issuer so that
  # `iss` validation stays strict: the issuer in the metadata must equal the
  # configured value, otherwise the token signature cannot be trusted.
  class Discovery
    class Error < StandardError; end

    CACHE_TTL = 1.hour

    attr_reader :issuer

    def initialize(issuer: Settings['issuer'], verify_ssl: Settings.verify_ssl?,
                   timeout: Settings.timeout)
      @issuer = issuer.to_s.strip.sub(%r{/+\z}, '')
      @verify_ssl = verify_ssl
      @timeout = timeout
    end

    # @return [Hash] provider metadata
    def metadata
      @metadata ||= begin
        cached = Rails.cache.read(cache_key)
        cached || fetch_metadata
      end
    end

    def authorization_endpoint
      metadata['authorization_endpoint']
    end

    def token_endpoint
      metadata['token_endpoint']
    end

    def userinfo_endpoint
      metadata['userinfo_endpoint']
    end

    def end_session_endpoint
      metadata['end_session_endpoint']
    end

    def jwks_uri
      metadata['jwks_uri']
    end

    def issuer_matches?
      metadata['issuer'].to_s.sub(%r{/+\z}, '') == issuer
    end

    def reset!
      @metadata = nil
      Rails.cache.delete(cache_key)
    end

    private

    def cache_key
      "redmine_oidc/discovery/#{Digest::MD5.hexdigest(issuer)}"
    end

    def fetch_metadata
      raise Error, 'OIDC issuer is not configured' if issuer.blank?

      uri = URI.parse("#{issuer}/.well-known/openid-configuration")
      response = request(uri)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Discovery request failed with HTTP #{response.code}"
      end

      data = begin
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Error, "Discovery response is not valid JSON: #{e.message}"
      end

      unless data.is_a?(Hash) && data['issuer'].present?
        raise Error, 'Discovery response is missing the issuer field'
      end

      Rails.cache.write(cache_key, data, expires_in: CACHE_TTL)
      data
    end

    def request(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = @verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.get(uri.request_uri)
    rescue Timeout::Error, Errno::ECONNREFUSED, SocketError, OpenSSL::SSL::SSLError => e
      raise Error, "Discovery request to #{uri.host} failed: #{e.message}"
    end
  end
end
