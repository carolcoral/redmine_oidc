# frozen_string_literal: true

require_relative '../test_helper'

class SettingsTest < Minitest::Test
  def test_truthy_values
    %w[1 true TRUE yes on].each do |value|
      assert RedmineOidc::Settings.truthy?(value), "expected #{value.inspect} to be truthy"
    end
  end

  def test_falsey_values
    ['0', 'false', '', nil, 'off'].each do |value|
      refute RedmineOidc::Settings.truthy?(value), "expected #{value.inspect} to be falsey"
    end
  end

  def test_enabled_requires_the_flag
    with_settings('enabled' => '1') { assert RedmineOidc::Settings.enabled? }
    with_settings('enabled' => '0') { refute RedmineOidc::Settings.enabled? }
  end

  def test_configured_requires_enabled_issuer_and_client_id
    with_settings('enabled' => '1', 'issuer' => 'https://idp', 'client_id' => 'c') do
      assert RedmineOidc::Settings.configured?
    end
    with_settings('enabled' => '1', 'issuer' => '', 'client_id' => 'c') do
      refute RedmineOidc::Settings.configured?
    end
    with_settings('enabled' => '0', 'issuer' => 'https://idp', 'client_id' => 'c') do
      refute RedmineOidc::Settings.configured?
    end
  end

  def test_scopes_are_split_on_spaces_and_commas
    with_settings('scopes' => 'openid profile,email') do
      assert_equal %w[openid profile email], RedmineOidc::Settings.scopes
    end
  end

  def test_default_role_ids_are_integers
    with_settings('default_role_ids' => %w[3 5]) do
      assert_equal [3, 5], RedmineOidc::Settings.default_role_ids
    end
  end

  def test_timeout_falls_back_to_a_sane_default
    assert_equal 10, RedmineOidc::Settings.timeout
    with_settings('timeout' => '25') { assert_equal 25, RedmineOidc::Settings.timeout }
    with_settings('timeout' => '0') { assert_equal 10, RedmineOidc::Settings.timeout }
    with_settings('timeout' => 'abc') { assert_equal 10, RedmineOidc::Settings.timeout }
  end

  def test_defaults_are_merged_over_missing_stored_keys
    Setting.plugin_redmine_oidc = { 'enabled' => '1' }
    assert_equal 'openid profile email', RedmineOidc::Settings['scopes']
  ensure
    Setting.plugin_redmine_oidc = TestSettings::DEFAULTS.dup
  end

  def test_survives_corrupted_settings
    [nil, 'garbage', 42].each do |corrupted|
      Setting.plugin_redmine_oidc = corrupted
      refute RedmineOidc::Settings.enabled?, "expected #{corrupted.inspect} to be tolerated"
    end
  ensure
    Setting.plugin_redmine_oidc = TestSettings::DEFAULTS.dup
  end
end
