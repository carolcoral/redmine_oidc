# frozen_string_literal: true

require_relative '../test_helper'

class TokenResponseTest < Minitest::Test
  def test_exposes_the_standard_fields
    response = RedmineOidc::TokenResponse.new(
      'id_token' => 'id', 'access_token' => 'access', 'refresh_token' => 'refresh',
      'token_type' => 'Bearer', 'expires_in' => 1800, 'scope' => 'openid profile'
    )

    assert_equal 'id', response.id_token
    assert_equal 'access', response.access_token
    assert_equal 'refresh', response.refresh_token
    assert_equal 'Bearer', response.token_type
    assert_equal 1800, response.expires_in
    assert_equal 'openid profile', response.scope
  end

  def test_defaults_token_type_to_bearer
    assert_equal 'Bearer', RedmineOidc::TokenResponse.new({}).token_type
  end

  def test_coerces_expires_in_to_an_integer
    assert_equal 0, RedmineOidc::TokenResponse.new({}).expires_in
    assert_equal 60, RedmineOidc::TokenResponse.new('expires_in' => '60').expires_in
  end

  def test_returns_nil_for_optional_fields_that_are_absent
    response = RedmineOidc::TokenResponse.new({})
    assert_nil response.id_token
    assert_nil response.access_token
    assert_nil response.refresh_token
    assert_nil response.scope
  end

  def test_tolerates_non_hash_input
    response = RedmineOidc::TokenResponse.new(nil)
    assert_nil response.id_token
    assert_equal 'Bearer', response.token_type
  end

  def test_exposes_the_raw_payload
    raw = { 'id_token' => 'id' }
    assert_equal raw, RedmineOidc::TokenResponse.new(raw).raw
  end
end
