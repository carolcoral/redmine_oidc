# frozen_string_literal: true

require_relative '../test_helper'

# Loads the real SettingsController against a stub ApplicationController.
#
# Only the class body runs (before_action / layout are no-ops here), so this
# verifies the wiring and the two actions' decision logic without a Rails boot.
class SettingsControllerTest < Minitest::Test
  class FakeApplicationController
    def self.before_action(*); end
    def self.layout(*); end

    attr_reader :redirected_to, :rendered_json, :rendered_status
    attr_accessor :request

    def initialize(params = {})
      @params = FakeParams.new(params)
      @request = Struct.new(:base_url).new('https://redmine.example.com')
    end

    def params
      @params
    end

    def params=(value)
      @params = value.is_a?(FakeParams) ? value : FakeParams.new(value)
    end

    def flash
      @flash ||= {}
    end

    # Rails accepts both `redirect_to action: 'show'` (implicit hash) and
    # `redirect_to some_url`; capture either form.
    def redirect_to(target = nil, **_options)
      @redirected_to = target || _options
    end

    def render(options)
      @rendered_json = options[:json]
      @rendered_status = options[:status]
    end

    def l(key)
      key.to_s
    end
  end

  # Indifferent params matching the slice of ActionController::Parameters used.
  class FakeParams
    def initialize(hash)
      @hash = hash.each_with_object({}) { |(k, v), memo| memo[k.to_s] = v }
    end

    def [](key)
      @hash[key.to_s]
    end

    def permit(*keys, **nested)
      allowed = keys.map(&:to_s) + nested.keys.map(&:to_s)
      self.class.new(@hash.slice(*allowed))
    end

    def to_h
      @hash.dup
    end

    def respond_to_missing?(name, include_private = false)
      super
    end
  end

  class FakeRole
    attr_reader :id, :name

    def initialize(id, name)
      @id = id
      @name = name
    end

    def self.givable
      self
    end

    def self.sorted
      [new(2, 'Manager'), new(3, 'Developer')]
    end
  end

  def setup
    Setting.plugin_redmine_oidc = TestSettings::DEFAULTS.dup
    Rails.cache.instance_variable_set(:@store, {})
    stub_role
    stub_rails_logger
    load_controller
  end

  def teardown
    Object.send(:remove_const, :Role) if Object.const_defined?(:Role)
    Object.const_set(:Role, @original_role) if @original_role
    Setting.plugin_redmine_oidc = TestSettings::DEFAULTS.dup
  end

  def stub_role
    @original_role = Object.const_get(:Role) if Object.const_defined?(:Role)
    Object.send(:remove_const, :Role) if Object.const_defined?(:Role)
    Object.const_set(:Role, FakeRole)
  end

  def stub_rails_logger
    Rails.define_singleton_method(:logger) { @logger ||= Logger.new(IO::NULL) }
  end

  # Loads the controller the way production does, via `require`, so SimpleCov
  # attributes the executed lines to the real file.
  #
  # ApplicationController is temporarily aliased to the stub, which is what the
  # controller inherits from.
  def load_controller
    Object.const_set(:ApplicationController, FakeApplicationController) unless Object.const_defined?(:ApplicationController)
    return @controller_class = RedmineOidc::SettingsController if RedmineOidc.const_defined?(:SettingsController)

    require File.expand_path('../../app/controllers/redmine_oidc/settings_controller', __dir__)
    @controller_class = RedmineOidc::SettingsController
  end


  def controller_with(params = {})
    @controller_class.new(params)
  end

  def test_show_assigns_settings_roles_and_callback_url
    c = controller_with
    c.show

    assert_equal 'https://idp.example.com', c.instance_variable_get(:@settings)['issuer']
    assert_equal %w[Manager Developer], c.instance_variable_get(:@default_roles).map(&:name)
    assert_equal 'https://redmine.example.com/oidc/callback', c.instance_variable_get(:@callback_url)
  end

  def test_update_persists_permitted_settings
    c = controller_with('settings' => { 'issuer' => 'https://new-idp.example.com', 'client_id' => 'new-client' })
    c.update

    assert_equal 'https://new-idp.example.com', RedmineOidc::Settings['issuer']
    assert_equal 'new-client', RedmineOidc::Settings['client_id']
    assert_equal({ action: 'show' }, c.redirected_to)
    assert_equal 'notice_successful_update', c.flash[:notice]
  end

  def test_update_keeps_the_secret_when_blank
    Setting.plugin_redmine_oidc = RedmineOidc::Settings.current.merge('client_secret' => 'keep-me')
    c = controller_with('settings' => { 'client_secret' => '', 'issuer' => 'https://x' })
    c.update

    assert_equal 'keep-me', RedmineOidc::Settings['client_secret']
  end

  def test_update_ignores_unpermitted_keys
    c = controller_with('settings' => { 'issuer' => 'https://safe', 'evil' => 'payload' })
    c.update

    refute RedmineOidc::Settings.current.key?('evil')
    assert_equal 'https://safe', RedmineOidc::Settings['issuer']
  end

  def test_update_reports_errors_without_raising
    c = controller_with('settings' => { 'issuer' => 'https://x' })
    # Force the merge to blow up and ensure the rescue path is exercised.
    RedmineOidc::SettingsForm.stub(:merge, ->(*) { raise 'boom' }) do
      c.update
    end

    assert_equal 'boom', c.flash[:error]
    assert_equal({ action: 'show' }, c.redirected_to)
  end

  def test_test_action_renders_a_success_payload
    stub_request(:get, 'https://idp.example.com/.well-known/openid-configuration')
      .to_return(status: 200, body: { 'issuer' => 'https://idp.example.com', 'jwks_uri' => 'https://idp.example.com/jwks' }.to_json)
    stub_request(:get, 'https://idp.example.com/jwks')
      .to_return(status: 200, body: { 'keys' => [{ 'kid' => 'k' }] }.to_json)

    c = controller_with
    c.test

    assert c.rendered_json[:success]
    assert_equal 1, c.rendered_json[:jwks_keys]
    assert_equal 'https://redmine.example.com/oidc/callback', c.rendered_json[:callback_url]
    assert_nil c.rendered_status
  end

  def test_test_action_renders_a_failure_payload
    stub_request(:get, 'https://idp.example.com/.well-known/openid-configuration')
      .to_return(status: 500, body: 'down')

    c = controller_with
    c.test

    refute c.rendered_json[:success]
    assert_equal :unprocessable_entity, c.rendered_status
  end
end
