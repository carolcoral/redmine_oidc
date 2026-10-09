# frozen_string_literal: true

require_relative '../test_helper'

class ConnectivityTest < Minitest::Test
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
      .to_return(status: 200, body: METADATA.to_json)
  end

  def client
    RedmineOidc::Client.new(
      issuer: 'https://idp.example.com', client_id: 'redmine', client_secret: 's',
      scopes: %w[openid], verify_ssl: true, timeout: 5
    )
  end

  def test_reports_success_with_endpoint_details
    stub_request(:get, 'https://idp.example.com/oauth2/jwks')
      .to_return(status: 200, body: { 'keys' => [{ 'kid' => 'a' }, { 'kid' => 'b' }] }.to_json)

    result = RedmineOidc::Connectivity.report(
      client: client, callback_url: 'https://redmine.example.com/oidc/callback'
    )

    assert result[:success]
    assert_equal 'https://idp.example.com', result[:issuer]
    assert_equal 2, result[:jwks_keys]
    assert result[:issuer_matches]
    assert_equal 'https://redmine.example.com/oidc/callback', result[:callback_url]
  end

  def test_reports_issuer_mismatch_without_failing_the_probe
    stub_request(:get, 'https://idp.example.com/.well-known/openid-configuration')
      .to_return(status: 200, body: METADATA.merge('issuer' => 'https://other').to_json)
    stub_request(:get, 'https://idp.example.com/oauth2/jwks')
      .to_return(status: 200, body: { 'keys' => [] }.to_json)

    result = RedmineOidc::Connectivity.report(client: client)
    assert result[:success]
    refute result[:issuer_matches]
  end

  def test_reports_discovery_failures
    stub_request(:get, 'https://idp.example.com/.well-known/openid-configuration')
      .to_return(status: 503, body: 'down')

    result = RedmineOidc::Connectivity.report(client: client)
    refute result[:success]
    assert_match(/HTTP 503/, result[:message])
  end

  def test_reports_jwks_failures
    stub_request(:get, 'https://idp.example.com/oauth2/jwks')
      .to_return(status: 500, body: 'boom')

    result = RedmineOidc::Connectivity.report(client: client)
    refute result[:success]
    assert_match(/HTTP 500/, result[:message])
  end

  def test_handles_a_provider_without_an_end_session_endpoint
    stub_request(:get, 'https://idp.example.com/.well-known/openid-configuration')
      .to_return(status: 200, body: METADATA.reject { |k, _| k == 'end_session_endpoint' }.to_json)
    stub_request(:get, 'https://idp.example.com/oauth2/jwks')
      .to_return(status: 200, body: { 'keys' => [] }.to_json)

    result = RedmineOidc::Connectivity.report(client: client)
    assert result[:success]
    assert_nil result[:end_session_endpoint]
  end
end
