# frozen_string_literal: true

require_relative '../test_helper'

class CallbackUrlTest < Minitest::Test
  FakeRequest = Struct.new(:base_url)

  def test_builds_from_the_request_base_url
    url = RedmineOidc::CallbackUrl.build(FakeRequest.new('https://redmine.example.com'))
    assert_equal 'https://redmine.example.com/oidc/callback', url
  end

  def test_setting_override_takes_precedence
    with_settings('redirect_uri' => 'https://public.example.com/oidc/callback') do
      url = RedmineOidc::CallbackUrl.build(FakeRequest.new('http://localhost:3000'))
      assert_equal 'https://public.example.com/oidc/callback', url
    end
  end

  def test_blank_override_is_ignored
    with_settings('redirect_uri' => '   ') do
      url = RedmineOidc::CallbackUrl.build(FakeRequest.new('http://localhost:3000'))
      assert_equal 'http://localhost:3000/oidc/callback', url
    end
  end
end
