# frozen_string_literal: true

require_relative '../test_helper'

class SettingsFormTest < Minitest::Test
  def test_normalizes_a_plain_hash
    result = RedmineOidc::SettingsForm.normalize('issuer' => 'https://idp', 'client_id' => 'c')
    assert_equal 'https://idp', result['issuer']
    assert_equal 'c', result['client_id']
  end

  def test_ignores_unpermitted_keys
    result = RedmineOidc::SettingsForm.normalize('issuer' => 'https://idp', 'evil' => 'payload')
    refute result.key?('evil')
    assert_equal 'https://idp', result['issuer']
  end

  def test_keeps_the_secret_when_blank
    refute RedmineOidc::SettingsForm.normalize('client_secret' => '').key?('client_secret')
    refute RedmineOidc::SettingsForm.normalize('client_secret' => '   ').key?('client_secret')
  end

  def test_keeps_the_secret_when_provided
    assert_equal 's3cret', RedmineOidc::SettingsForm.normalize('client_secret' => 's3cret')['client_secret']
  end

  def test_drops_blank_role_ids
    result = RedmineOidc::SettingsForm.normalize('default_role_ids' => ['', '2', ' ', '3'])
    assert_equal %w[2 3], result['default_role_ids']
  end

  def test_coerces_a_scalar_role_id_into_an_array
    result = RedmineOidc::SettingsForm.normalize('default_role_ids' => '4')
    assert_equal ['4'], result['default_role_ids']
  end

  def test_handles_nil_input
    assert_empty RedmineOidc::SettingsForm.normalize(nil)
  end

  def test_handles_an_object_responding_to_to_h
    fake = Object.new
    fake.define_singleton_method(:to_h) { { issuer: 'https://idp' } }
    assert_equal 'https://idp', RedmineOidc::SettingsForm.normalize(fake)['issuer']
  end

  def test_merge_preserves_untouched_settings
    current = RedmineOidc::Settings.current
    merged = RedmineOidc::SettingsForm.merge({ 'issuer' => 'https://new' }, current)

    assert_equal 'https://new', merged['issuer']
    assert_equal current['scopes'], merged['scopes']
    assert_equal current['client_secret'], merged['client_secret']
  end

  def test_merge_does_not_wipe_the_secret
    current = RedmineOidc::Settings.current.merge('client_secret' => 'keep-me')
    merged = RedmineOidc::SettingsForm.merge({ 'client_secret' => '', 'issuer' => 'https://x' }, current)
    assert_equal 'keep-me', merged['client_secret']
  end

  def test_permitted_keys_are_frozen_and_complete
    assert RedmineOidc::SettingsForm::PERMITTED.frozen?
    %w[enabled issuer client_id client_secret scopes default_role_ids].each do |key|
      assert_includes RedmineOidc::SettingsForm::PERMITTED, key
    end
  end
end
