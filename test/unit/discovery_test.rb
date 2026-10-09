# frozen_string_literal: true

require_relative '../test_helper'

class DiscoveryTest < Minitest::Test
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
  end

  def stub_discovery(body, status: 200)
    stub_request(:get, 'https://idp.example.com/.well-known/openid-configuration')
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def test_fetches_and_exposes_endpoints
    stub_discovery(METADATA.to_json)
    discovery = RedmineOidc::Discovery.new(issuer: 'https://idp.example.com')

    assert_equal METADATA['authorization_endpoint'], discovery.authorization_endpoint
    assert_equal METADATA['token_endpoint'], discovery.token_endpoint
    assert_equal METADATA['userinfo_endpoint'], discovery.userinfo_endpoint
    assert_equal METADATA['end_session_endpoint'], discovery.end_session_endpoint
    assert_equal METADATA['jwks_uri'], discovery.jwks_uri
  end

  def test_normalizes_trailing_slash_on_issuer
    stub_discovery(METADATA.to_json)
    discovery = RedmineOidc::Discovery.new(issuer: 'https://idp.example.com/')
    assert_equal 'https://idp.example.com', discovery.issuer
    assert discovery.issuer_matches?
  end

  def test_detects_issuer_mismatch
    stub_discovery(METADATA.merge('issuer' => 'https://other.example.com').to_json)
    discovery = RedmineOidc::Discovery.new(issuer: 'https://idp.example.com')
    refute discovery.issuer_matches?
  end

  def test_raises_on_http_error
    stub_discovery('nope', status: 500)
    discovery = RedmineOidc::Discovery.new(issuer: 'https://idp.example.com')
    error = assert_raises(RedmineOidc::Discovery::Error) { discovery.metadata }
    assert_match(/HTTP 500/, error.message)
  end

  def test_raises_on_invalid_json
    stub_discovery('{not json')
    discovery = RedmineOidc::Discovery.new(issuer: 'https://idp.example.com')
    assert_raises(RedmineOidc::Discovery::Error) { discovery.metadata }
  end

  def test_raises_when_issuer_is_missing_from_metadata
    stub_discovery({ 'authorization_endpoint' => 'x' }.to_json)
    discovery = RedmineOidc::Discovery.new(issuer: 'https://idp.example.com')
    error = assert_raises(RedmineOidc::Discovery::Error) { discovery.metadata }
    assert_match(/missing the issuer/, error.message)
  end

  def test_raises_when_issuer_is_not_configured
    discovery = RedmineOidc::Discovery.new(issuer: '')
    assert_raises(RedmineOidc::Discovery::Error) { discovery.metadata }
  end

  def test_caches_metadata_between_calls
    stub_discovery(METADATA.to_json)
    discovery = RedmineOidc::Discovery.new(issuer: 'https://idp.example.com')
    3.times { discovery.metadata }
    assert_requested :get, 'https://idp.example.com/.well-known/openid-configuration', times: 1
  end

  def test_reset_forces_a_refetch
    stub_discovery(METADATA.to_json)
    discovery = RedmineOidc::Discovery.new(issuer: 'https://idp.example.com')
    discovery.metadata
    discovery.reset!
    discovery.metadata
    assert_requested :get, 'https://idp.example.com/.well-known/openid-configuration', times: 2
  end
end
