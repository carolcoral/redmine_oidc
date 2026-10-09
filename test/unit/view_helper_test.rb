# frozen_string_literal: true

require_relative '../test_helper'

class ViewHelperTest < Minitest::Test
  include RedmineOidc::ViewHelper

  # Minimal stand-in for Rails' routing helper used by the partials.
  def oidc_login_path(options = {})
    query = options.any? ? "?#{options.to_query}" : ''
    "/oidc/login#{query}"
  end

  def test_builds_a_login_link_with_a_back_url
    assert_equal '/oidc/login?back_url=%2Fissues', oidc_login_link('/issues')
  end

  def test_builds_a_login_link_without_a_back_url
    assert_equal '/oidc/login', oidc_login_link
  end

  def test_uses_the_configured_button_label
    with_settings('button_label' => 'Unified Login') do
      assert_equal 'Unified Login', oidc_button_label
    end
  end

  def test_falls_back_to_a_default_button_label
    with_settings('button_label' => '') do
      assert_equal 'OIDC', oidc_button_label
    end
  end

  def test_reports_the_configured_provider
    with_settings('issuer' => 'https://sso.example.com') do
      assert_equal 'https://sso.example.com', oidc_provider_name
    end
  end

  def test_falls_back_to_a_default_provider_name
    with_settings('issuer' => '') do
      assert_equal 'OIDC', oidc_provider_name
    end
  end
end
