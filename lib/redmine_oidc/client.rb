# frozen_string_literal: true

require 'json'
require 'uri'
require 'net/http'
require 'securerandom'

module RedmineOidc
  # Minimal OIDC relying-party client: authorization URL, code exchange,
  # userinfo lookup and JWKS retrieval.
  class Client
    class Error < StandardError; end

    attr_reader :discovery

    def initialize(config = nil)
      config ||= {
        issuer: Settings['issuer'],
        client_id: Settings['client_id'],
        client_secret: Settings['client_secret'],
        scopes: Settings.scopes,
        verify_ssl: Settings.verify_ssl?,
        timeout: Settings.timeout
      }
      @issuer = config[:issuer].to_s.strip
      @client_id = config[:client_id].to_s.strip
      @client_secret = config[:client_secret].to_s
      @scopes = Array(config[:scopes]).presence || ['openid', 'profile', 'email']
      @verify_ssl = config.fetch(:verify_ssl, true)
      @timeout = config[:timeout].to_i.positive? ? config[:timeout].to_i : 10
      @discovery = Discovery.new(issuer: @issuer, verify_ssl: @verify_ssl, timeout: @timeout)
    end

    attr_reader :client_id, :client_secret

    def issuer
      @issuer
    end

    def scopes
      @scopes
    end

    # Builds the authorization redirect URL for the given callback.
    #
    # @param redirect_uri [String] absolute callback URL registered at the provider
    # @param state [String] opaque CSRF token
    # @param nonce [String] replay-protection nonce
    # @return [String]
    def authorization_url(redirect_uri:, state:, nonce:)
      params = {
        response_type: 'code',
        client_id: @client_id,
        redirect_uri: redirect_uri,
        scope: @scopes.join(' '),
        state: state,
        nonce: nonce
      }
      "#{discovery.authorization_endpoint}?#{params.to_query}"
    end

    # Exchanges an authorization code for tokens.
    #
    # @return [TokenResponse]
    def exchange_code(code:, redirect_uri:)
      body = {
        grant_type: 'authorization_code',
        code: code,
        redirect_uri: redirect_uri
      }
      TokenResponse.new(post_form(discovery.token_endpoint, body, basic_auth: true))
    end

    # Refreshes tokens using a refresh_token grant.
    #
    # @return [TokenResponse]
    def refresh(refresh_token:)
      body = { grant_type: 'refresh_token', refresh_token: refresh_token }
      TokenResponse.new(post_form(discovery.token_endpoint, body, basic_auth: true))
    end

    # Fetches user claims from the userinfo endpoint.
    def userinfo(access_token)
      response = get(discovery.userinfo_endpoint, 'Authorization' => "Bearer #{access_token}")
      parse_json(response)
    end

    # Retrieves the provider signing keys.
    def jwks
      response = get(discovery.jwks_uri)
      parse_json(response)['keys'] || []
    end

    # Verifies and decodes an ID token against the provider JWKS.
    def verify_id_token(token, nonce: nil)
      IdToken.new(token, client: self, nonce: nonce, jwks: jwks).claims
    end

    # Builds an RP-initiated logout URL when the provider advertises one.
    def end_session_url(id_token_hint: nil, post_logout_redirect_uri: nil)
      endpoint = discovery.end_session_endpoint
      return nil if endpoint.blank?

      params = {}
      params[:id_token_hint] = id_token_hint if id_token_hint.present?
      params[:post_logout_redirect_uri] = post_logout_redirect_uri if post_logout_redirect_uri.present?
      params.present? ? "#{endpoint}?#{params.to_query}" : endpoint
    end

    # Generates a random opaque value for state / nonce parameters.
    def self.generate_token
      SecureRandom.urlsafe_base64(32)
    end

    private

    def post_form(url, body, basic_auth: false)
      raise Error, 'Token endpoint is unknown' if url.blank?

      uri = URI.parse(url)
      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/x-www-form-urlencoded'
      request['Accept'] = 'application/json'
      if basic_auth
        request.basic_auth(URI.encode_www_form_component(@client_id), URI.encode_www_form_component(@client_secret))
      end
      request.body = URI.encode_www_form(body)

      response = perform(uri, request)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Token endpoint returned HTTP #{response.code}: #{truncate(response.body)}"
      end

      parse_json(response)
    end

    def get(url, headers = {})
      raise Error, 'Endpoint is unknown' if url.blank?

      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri.request_uri)
      request['Accept'] = 'application/json'
      headers.each { |key, value| request[key] = value }

      response = perform(uri, request)
      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Endpoint returned HTTP #{response.code}: #{truncate(response.body)}"
      end

      response
    end

    def perform(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = @verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http.start { |connection| connection.request(request) }
    rescue Timeout::Error, Errno::ECONNREFUSED, SocketError, OpenSSL::SSL::SSLError => e
      raise Error, "Request to #{uri.host} failed: #{e.message}"
    end

    def parse_json(response)
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "Response is not valid JSON: #{e.message}"
    end

    def truncate(body, limit = 300)
      body.to_s[0, limit]
    end
  end
end
