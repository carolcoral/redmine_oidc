# frozen_string_literal: true

require 'base64'
require 'json'
require 'openssl'

module RedmineOidc
  # Verifies and decodes an RS256-signed ID Token.
  #
  # Verification is deliberately explicit rather than delegated to a gem, so the
  # plugin stays dependency-free inside Redmine. Checks performed:
  #   * header algorithm is RS256 (never trusts `none` / HMAC confusion)
  #   * signature against the provider JWKS (kid lookup, RSA + SHA-256)
  #   * `iss`, `aud`, `exp`, `nbf`, `iat` and optional `nonce`
  class IdToken
    class Error < StandardError; end

    CLOCK_SKEW = 60

    attr_reader :claims

    def initialize(token, client:, nonce: nil, jwks: nil)
      @token = token.to_s
      @client = client
      @expected_nonce = nonce
      @jwks = jwks
      @claims = decode!
    end

    def sub
      claims['sub'].to_s
    end

    private

    def decode!
      segments = @token.split('.')
      raise Error, 'ID token is malformed' unless segments.length == 3

      header = decode_segment(segments[0])
      payload = decode_segment(segments[1])
      signature = Base64.urlsafe_decode64(segments[2])

      verify_algorithm!(header)
      verify_signature!(segments[0, 2].join('.'), signature, header)
      verify_claims!(payload)
      payload
    end

    def decode_segment(segment)
      JSON.parse(Base64.urlsafe_decode64(segment))
    rescue ArgumentError, JSON::ParserError => e
      raise Error, "ID token segment cannot be decoded: #{e.message}"
    end

    def verify_algorithm!(header)
      return if header['alg'] == 'RS256'

      raise Error, "Unsupported ID token signing algorithm: #{header['alg'].inspect}"
    end

    def verify_claims!(payload)
      verify_issuer!(payload)
      verify_audience!(payload)
      verify_timestamps!(payload)
      verify_nonce!(payload)
    end

    def verify_issuer!(payload)
      expected = @client.discovery.issuer
      actual = payload['iss'].to_s.sub(%r{/+\z}, '')
      return if actual == expected

      raise Error, "ID token issuer mismatch: expected #{expected.inspect}, got #{payload['iss'].inspect}"
    end

    def verify_audience!(payload)
      aud = payload['aud']
      audiences = aud.is_a?(Array) ? aud : [aud]
      return if audiences.map(&:to_s).include?(@client.client_id)

      raise Error, 'ID token audience does not include this client_id'
    end

    def verify_timestamps!(payload)
      now = Time.now.to_i
      exp = payload['exp']
      raise Error, 'ID token is missing the exp claim' unless exp.is_a?(Numeric)
      raise Error, 'ID token has expired' if now > exp + CLOCK_SKEW

      if payload['nbf'].is_a?(Numeric) && now + CLOCK_SKEW < payload['nbf']
        raise Error, 'ID token is not valid yet'
      end
    end

    def verify_nonce!(payload)
      return if @expected_nonce.blank?

      return if payload['nonce'].to_s == @expected_nonce.to_s

      raise Error, 'ID token nonce mismatch'
    end

    def verify_signature!(signing_input, signature, header)
      keys = select_keys(header['kid'])
      raise Error, 'No matching key found in the provider JWKS' if keys.empty?

      keys.each do |jwk|
        public_key = build_rsa_key(jwk)
        next if public_key.nil?

        return true if public_key.verify(OpenSSL::Digest.new('SHA256'), signature, signing_input)
      end

      raise Error, 'ID token signature verification failed'
    end

    def select_keys(kid)
      keys = Array(@jwks)
      return keys if kid.blank?

      matched = keys.select { |key| key['kid'].to_s == kid.to_s }
      matched.presence || keys
    end

    def build_rsa_key(jwk)
      return nil unless jwk.is_a?(Hash) && jwk['kty'] == 'RSA'

      n = OpenSSL::BN.new(Base64.urlsafe_decode64(jwk['n'].to_s), 2)
      e = OpenSSL::BN.new(Base64.urlsafe_decode64(jwk['e'].to_s), 2)
      sequence = OpenSSL::ASN1::Sequence.new(
        [
          OpenSSL::ASN1::Integer.new(n),
          OpenSSL::ASN1::Integer.new(e)
        ]
      )
      OpenSSL::PKey::RSA.new(sequence.to_der)
    rescue StandardError => e
      Rails.logger.warn "[redmine_oidc] Failed to build RSA key from JWKS: #{e.message}"
      nil
    end
  end
end
