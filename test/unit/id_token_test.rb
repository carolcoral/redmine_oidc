# frozen_string_literal: true

require_relative '../test_helper'

# Verifies the RS256 ID token checks: signature, algorithm, issuer, audience,
# expiry and nonce. A real RSA key pair is generated per test so the signature
# path is genuinely exercised rather than stubbed out.
class IdTokenTest < Minitest::Test
  ISSUER = 'https://idp.example.com'
  CLIENT_ID = 'redmine'

  def setup
    @key = OpenSSL::PKey::RSA.generate(2048)
    @kid = 'test-key-1'
  end

  def jwks
    [{
      'kty' => 'RSA',
      'kid' => @kid,
      'alg' => 'RS256',
      'use' => 'sig',
      'n' => Base64.urlsafe_encode64(@key.n.to_s(2), padding: false),
      'e' => Base64.urlsafe_encode64(@key.e.to_s(2), padding: false)
    }]
  end

  def fake_client(issuer: ISSUER, client_id: CLIENT_ID)
    discovery = Object.new
    discovery.define_singleton_method(:issuer) { issuer }
    client = Object.new
    client.define_singleton_method(:discovery) { discovery }
    client.define_singleton_method(:client_id) { client_id }
    client
  end

  def build_token(payload_overrides = {}, header_overrides = {})
    now = Time.now.to_i
    payload = {
      'iss' => ISSUER,
      'aud' => CLIENT_ID,
      'sub' => 'user-1',
      'iat' => now,
      'exp' => now + 300
    }.merge(payload_overrides)
    header = { 'alg' => 'RS256', 'typ' => 'JWT', 'kid' => @kid }.merge(header_overrides)
    sign(header, payload)
  end

  def sign(header, payload, key = @key)
    encoded_header = Base64.urlsafe_encode64(header.to_json, padding: false)
    encoded_payload = Base64.urlsafe_encode64(payload.to_json, padding: false)
    signing_input = "#{encoded_header}.#{encoded_payload}"
    signature = key.sign(OpenSSL::Digest.new('SHA256'), signing_input)
    "#{signing_input}.#{Base64.urlsafe_encode64(signature, padding: false)}"
  end

  def verify(token, nonce: nil, client: nil)
    RedmineOidc::IdToken.new(token, client: client || fake_client, nonce: nonce, jwks: jwks)
  end

  def test_accepts_a_correctly_signed_token
    token = verify(build_token)
    assert_equal 'user-1', token.sub
  end

  def test_rejects_a_token_signed_by_an_unknown_key
    other_key = OpenSSL::PKey::RSA.generate(2048)
    now = Time.now.to_i
    token = sign(
      { 'alg' => 'RS256', 'kid' => @kid },
      { 'iss' => ISSUER, 'aud' => CLIENT_ID, 'sub' => 'evil', 'exp' => now + 300 },
      other_key
    )

    assert_raises(RedmineOidc::IdToken::Error) { verify(token) }
  end

  def test_rejects_tampered_payload
    token = build_token
    header, _payload, signature = token.split('.')
    forged = Base64.urlsafe_encode64(
      { 'iss' => ISSUER, 'aud' => CLIENT_ID, 'sub' => 'admin', 'exp' => Time.now.to_i + 300 }.to_json,
      padding: false
    )

    assert_raises(RedmineOidc::IdToken::Error) { verify("#{header}.#{forged}.#{signature}") }
  end

  def test_rejects_the_none_algorithm
    now = Time.now.to_i
    header = { 'alg' => 'none' }
    payload = { 'iss' => ISSUER, 'aud' => CLIENT_ID, 'sub' => 'user-1', 'exp' => now + 300 }
    token = "#{Base64.urlsafe_encode64(header.to_json, padding: false)}." \
            "#{Base64.urlsafe_encode64(payload.to_json, padding: false)}."

    assert_raises(RedmineOidc::IdToken::Error) { verify(token) }
  end

  def test_rejects_hmac_signed_token
    now = Time.now.to_i
    header = { 'alg' => 'HS256', 'kid' => @kid }
    payload = { 'iss' => ISSUER, 'aud' => CLIENT_ID, 'sub' => 'user-1', 'exp' => now + 300 }
    encoded_header = Base64.urlsafe_encode64(header.to_json, padding: false)
    encoded_payload = Base64.urlsafe_encode64(payload.to_json, padding: false)
    signature = OpenSSL::HMAC.digest('SHA256', 'secret', "#{encoded_header}.#{encoded_payload}")
    token = "#{encoded_header}.#{encoded_payload}.#{Base64.urlsafe_encode64(signature, padding: false)}"

    assert_raises(RedmineOidc::IdToken::Error) { verify(token) }
  end

  def test_rejects_issuer_mismatch
    token = build_token('iss' => 'https://evil.example.com')
    error = assert_raises(RedmineOidc::IdToken::Error) { verify(token) }
    assert_match(/issuer mismatch/, error.message)
  end

  def test_tolerates_trailing_slash_in_issuer
    token = build_token('iss' => "#{ISSUER}/")
    assert_equal 'user-1', verify(token).sub
  end

  def test_rejects_audience_mismatch
    token = build_token('aud' => 'another-client')
    error = assert_raises(RedmineOidc::IdToken::Error) { verify(token) }
    assert_match(/audience/, error.message)
  end

  def test_accepts_audience_array_containing_client
    token = build_token('aud' => %w[another-client redmine])
    assert_equal 'user-1', verify(token).sub
  end

  def test_rejects_expired_token
    token = build_token('exp' => Time.now.to_i - 3600)
    error = assert_raises(RedmineOidc::IdToken::Error) { verify(token) }
    assert_match(/expired/, error.message)
  end

  def test_allows_small_clock_skew
    token = build_token('exp' => Time.now.to_i - 10)
    assert_equal 'user-1', verify(token).sub
  end

  def test_rejects_token_without_exp
    token = build_token('exp' => nil)
    assert_raises(RedmineOidc::IdToken::Error) { verify(token) }
  end

  def test_rejects_not_yet_valid_token
    token = build_token('nbf' => Time.now.to_i + 3600)
    error = assert_raises(RedmineOidc::IdToken::Error) { verify(token) }
    assert_match(/not valid yet/, error.message)
  end

  def test_enforces_nonce_when_expected
    token = build_token('nonce' => 'expected')
    assert_equal 'user-1', verify(token, nonce: 'expected').sub
    assert_raises(RedmineOidc::IdToken::Error) { verify(token, nonce: 'other') }
  end

  def test_ignores_nonce_when_not_expected
    token = build_token('nonce' => 'whatever')
    assert_equal 'user-1', verify(token).sub
  end

  def test_rejects_malformed_token
    assert_raises(RedmineOidc::IdToken::Error) { verify('not.a.jwt.at.all') }
  end

  def test_rejects_undecodable_segment
    assert_raises(RedmineOidc::IdToken::Error) { verify('@@@.@@@.@@@') }
  end

  def test_rejects_unknown_kid_with_no_fallback_keys
    now = Time.now.to_i
    token = sign(
      { 'alg' => 'RS256', 'kid' => 'missing' },
      { 'iss' => ISSUER, 'aud' => CLIENT_ID, 'sub' => 'user-1', 'exp' => now + 300 }
    )
    # With a kid that matches nothing the verifier falls back to all keys, which
    # still succeeds here; the important case is an empty JWKS.
    assert_equal 'user-1', verify(token).sub

    error = assert_raises(RedmineOidc::IdToken::Error) do
      RedmineOidc::IdToken.new(token, client: fake_client, jwks: [])
    end
    assert_match(/No matching key/, error.message)
  end
end
