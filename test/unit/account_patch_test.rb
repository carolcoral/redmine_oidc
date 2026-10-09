# frozen_string_literal: true

require_relative '../test_helper'

# Covers the login-page guard: auto-redirect, blocking the local password form,
# and the administrator escape hatch.
class AccountPatchTest < Minitest::Test
  # Mimics the slice of AccountController the patch interacts with.
  class FakeController
    include RedmineOidc::Patches::AccountPatch

    attr_reader :redirected_to, :rendered
    attr_accessor :request

    def initialize(params = {}, post: false)
      @params = FakeParams.new(params)
      @post = post
      @redirected_to = nil
      @rendered = nil
    end

    def request
      @request ||= Struct.new(:post?).new(@post)
    end

    def params
      @params
    end

    def params=(value)
      @params = value.is_a?(FakeParams) ? value : FakeParams.new(value)
    end

    # `flash.now` needs an object that accepts arbitrary keys.
    def flash
      @flash ||= FlashHash.new
    end

    # Stand-in for the controller's own login action.
    def login_without_oidc
      :local_login
    end
  end

  # Mirrors Rails' indifferent params so `params[:local]` and `params['local']`
  # both resolve, which is what the patch relies on.
  class FakeParams
    def initialize(hash)
      @hash = {}
      hash.each { |key, value| @hash[key.to_s] = value }
    end

    def [](key)
      @hash[key.to_s]
    end

    def key?(key)
      @hash.key?(key.to_s)
    end

    def to_h
      @hash.dup
    end
  end

  class FlashHash
    def initialize
      @store = {}
    end

    def now
      @store
    end

    def [](key)
      @store[key]
    end

    def []=(key, value)
      @store[key] = value
    end
  end

  def setup
    @original_user = Object.const_get(:User) if Object.const_defined?(:User)
    Object.send(:remove_const, :User) if Object.const_defined?(:User)
    Object.const_set(:User, FakeUser)
  end

  def teardown
    Object.send(:remove_const, :User)
    Object.const_set(:User, @original_user) if @original_user
  end

  class FakeUser
    attr_accessor :admin

    def initialize(admin: false)
      @admin = admin
    end

    def admin?
      @admin
    end

    # `User.try(:find_by_login, name)` must return nil without raising.
    def self.find_by_login(login)
      return nil if login.nil?

      login.to_s == 'root.admin' ? new(admin: true) : new(admin: false)
    end
  end

  def with_controller(params = {}, post: false, &block)
    controller = FakeController.new(params, post: post)
    controller.define_singleton_method(:oidc_login_path) { |_opts = {}| '/oidc/login' }
    controller.define_singleton_method(:redirect_to) { |target, **_o| @redirected_to = target }
    controller.define_singleton_method(:render) { |options| @rendered = options }
    controller.define_singleton_method(:head) { |_status| @rendered = :head }
    controller.define_singleton_method(:l) { |key| key.to_s }
    block.call(controller)
  end

  def test_delegates_to_local_login_by_default
    with_settings('enabled' => '0') do
      with_controller { |c| assert_equal :local_login, c.login_with_oidc }
    end
  end

  def test_auto_redirects_to_the_provider
    with_settings('enabled' => '1', 'issuer' => 'https://idp', 'client_id' => 'c',
                  'auto_redirect' => '1') do
      with_controller { |c| c.login_with_oidc; assert_equal '/oidc/login', c.redirected_to }
    end
  end

  def test_local_parameter_bypasses_auto_redirect
    with_settings('enabled' => '1', 'issuer' => 'https://idp', 'client_id' => 'c',
                  'auto_redirect' => '1') do
      with_controller({ 'local' => '1' }) do |c|
        assert_equal :local_login, c.login_with_oidc
      end
    end
  end

  def test_does_not_auto_redirect_when_disabled
    with_settings('enabled' => '1', 'issuer' => 'https://idp', 'client_id' => 'c',
                  'auto_redirect' => '0') do
      with_controller { |c| assert_equal :local_login, c.login_with_oidc }
    end
  end

  def test_blocks_password_login_for_regular_users_when_hidden
    with_settings('enabled' => '1', 'issuer' => 'https://idp', 'client_id' => 'c',
                  'hide_local_login' => '1') do
      with_controller({ 'username' => 'alice' }, post: true) do |c|
        c.login_with_oidc
        assert_equal 'account/login', c.rendered[:template]
        assert_equal 'base', c.rendered[:layout]
      end
    end
  end

  def test_allows_password_login_for_administrators
    with_settings('enabled' => '1', 'issuer' => 'https://idp', 'client_id' => 'c',
                  'hide_local_login' => '1') do
      with_controller({ 'username' => 'root.admin' }, post: true) do |c|
        assert_equal :local_login, c.login_with_oidc
      end
    end
  end

  def test_shows_the_form_on_get_when_hidden
    with_settings('enabled' => '1', 'issuer' => 'https://idp', 'client_id' => 'c',
                  'hide_local_login' => '1') do
      with_controller({}, post: false) do |c|
        assert_equal :local_login, c.login_with_oidc
      end
    end
  end

  def test_hidden_login_does_not_apply_when_oidc_is_unconfigured
    with_settings('enabled' => '1', 'issuer' => '', 'client_id' => '',
                  'hide_local_login' => '1') do
      with_controller({ 'username' => 'alice' }, post: true) do |c|
        assert_equal :local_login, c.login_with_oidc
      end
    end
  end
end
