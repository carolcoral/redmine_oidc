# frozen_string_literal: true

require_relative '../test_helper'

class ClientTest < Minitest::Test
  METADATA = {
    'issuer' => 'https://idp.example.com',
    'authorization_endpoint' => 'https://idp.example.com/oauth2/authorize',
    'token_endpoint' => 'https://idp.example.com/oauth2/token',
    'userinfo_endpoint' => 'https://idp.example.com/userinfo',
    'jwks_uri' => 'https://idp.example.com/oauth2/jwks',
    'end_session_endpoint' => 'https://idp.example.com/connect/logout'
  }.freeze

  def setup
    Rails.cache.instance_variable_set(:@store, {})
    stub_request(:get, 'https://idp.example.com/.well-known/openid-configuration')
      .to_return(status: 200, body: METADATA.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def client
    RedmineOidc::Client.new(
      issuer: 'https://idp.example.com',
      client_id: 'redmine',
      client_secret: 'secret',
      scopes: %w[openid profile],
      verify_ssl: true,
      timeout: 5
    )
  end

  def test_builds_an_authorization_url_with_all_parameters
    url = client.authorization_url(
      redirect_uri: 'https://redmine.example.com/oidc/callback',
      state: 'state-1',
      nonce: 'nonce-1'
    )

    assert_includes url, 'https://idp.example.com/oauth2/authorize?'
    assert_includes url, 'response_type=code'
    assert_includes url, 'client_id=redmine'
    assert_includes url, 'state=state-1'
    assert_includes url, 'nonce=nonce-1'
    assert_includes url, CGI.escape('openid profile')
  end

  def test_exchanges_a_code_for_tokens
    stub_request(:post, 'https://idp.example.com/oauth2/token')
      .to_return(status: 200,
                 body: { 'id_token' => 'id', 'access_token' => 'access',
                         'refresh_token' => 'refresh', 'expires_in' => 1800 }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    token = client.exchange_code(code: 'abc', redirect_uri: 'https://redmine.example.com/oidc/callback')
    assert_equal 'id', token.id_token
    assert_equal 'access', token.access_token
    assert_equal 'refresh', token.refresh_token
    assert_equal 1800, token.expires_in
  end

  def test_sends_client_credentials_as_basic_auth
    stub = stub_request(:post, 'https://idp.example.com/oauth2/token')
           .with(headers: { 'Authorization' => "Basic #{Base64.strict_encode64('redmine:secret')}" })
           .to_return(status: 200, body: '{"access_token":"a"}')

    client.exchange_code(code: 'abc', redirect_uri: 'https://redmine.example.com/oidc/callback')
    assert_requested stub
  end

  # Credentials must reach Basic auth verbatim: providers such as Keycloak,
  # Authentik and Azure AD issue secrets containing `+`, `/`, `=` and `%`,
  # which form-encoding would corrupt into `invalid_client`.
  def test_does_not_form_encode_special_characters_in_client_credentials
    secret = 'a+b/c==d%e f'
    special_client = RedmineOidc::Client.new(
      issuer: 'https://idp.example.com',
      client_id: 'redmine+app',
      client_secret: secret,
      scopes: %w[openid],
      verify_ssl: true,
      timeout: 5
    )

    expected = "Basic #{Base64.strict_encode64("redmine+app:#{secret}")}"
    stub = stub_request(:post, 'https://idp.example.com/oauth2/token')
           .with(headers: { 'Authorization' => expected })
           .to_return(status: 200, body: '{"access_token":"a"}')

    special_client.exchange_code(code: 'abc', redirect_uri: 'https://redmine.example.com/oidc/callback')
    assert_requested stub
  end

  def test_raises_on_a_failed_token_exchange
    stub_request(:post, 'https://idp.example.com/oauth2/token')
      .to_return(status: 400, body: '{"error":"invalid_grant"}')

    error = assert_raises(RedmineOidc::Client::Error) do
      client.exchange_code(code: 'bad', redirect_uri: 'https://redmine.example.com/oidc/callback')
    end
    assert_match(/HTTP 400/, error.message)
  end

  def test_reads_userinfo_with_a_bearer_token
    stub_request(:get, 'https://idp.example.com/userinfo')
      .with(headers: { 'Authorization' => 'Bearer access-token' })
      .to_return(status: 200, body: { 'sub' => 'user-1', 'name' => 'Alice' }.to_json)

    assert_equal 'user-1', client.userinfo('access-token')['sub']
  end

  def test_raises_when_userinfo_fails
    stub_request(:get, 'https://idp.example.com/userinfo').to_return(status: 401, body: '{}')
    assert_raises(RedmineOidc::Client::Error) { client.userinfo('bad') }
  end

  def test_fetches_signing_keys
    stub_request(:get, 'https://idp.example.com/oauth2/jwks')
      .to_return(status: 200, body: { 'keys' => [{ 'kid' => 'k1' }] }.to_json)

    assert_equal ['k1'], client.jwks.map { |key| key['kid'] }
  end

  def test_returns_no_end_session_url_when_unsupported
    stub_request(:get, 'https://idp.example.com/.well-known/openid-configuration')
      .to_return(status: 200, body: METADATA.reject { |k, _| k == 'end_session_endpoint' }.to_json)

    assert_nil client.end_session_url
  end

  def test_builds_an_end_session_url_with_hints
    url = client.end_session_url(
      id_token_hint: 'id-token',
      post_logout_redirect_uri: 'https://redmine.example.com/'
    )
    assert_includes url, 'https://idp.example.com/connect/logout?'
    assert_includes url, 'id_token_hint=id-token'
    assert_includes url, CGI.escape('https://redmine.example.com/')
  end

  def test_generates_unique_state_tokens
    values = Array.new(10) { RedmineOidc::Client.generate_token }
    assert_equal 10, values.uniq.size
    assert(values.all? { |value| value.length >= 20 })
  end

  def test_reports_network_failures_as_client_errors
    stub_request(:get, 'https://idp.example.com/.well-known/openid-configuration')
      .to_raise(Errno::ECONNREFUSED)

    error = assert_raises(RedmineOidc::Discovery::Error) { client.discovery.metadata }
    assert_match(/Connection refused/, error.message)
  end
end
