# frozen_string_literal: true

require_relative '../test_helper'

# Exercises the extension-point wiring (patches + hooks) by defining the same
# stub constants Redmine provides at boot, without needing a full Rails stack.
class PatchesTest < Minitest::Test
  def setup
    @defined = {}
    %i[AccountController ApplicationController User ViewListener].each do |name|
      @defined[name] = Object.const_defined?(name)
      Object.send(:remove_const, name) if @defined[name]
    end
  end

  def teardown
    %i[AccountController ApplicationController User ViewListener].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name)
    end
  end

  def define_stub(name, &body)
    klass = Class.new
    klass.class_eval(&body) if body
    Object.const_set(name, klass)
    klass
  end

  def test_account_patch_adds_the_oidc_login_helper
    define_stub(:AccountController) do
      def login; end
    end

    RedmineOidc::Hooks.install!

    assert_includes AccountController.ancestors, RedmineOidc::Patches::AccountPatch
    controller = AccountController.new
    with_settings('enabled' => '1', 'issuer' => 'https://idp', 'client_id' => 'c') do
      assert controller.oidc_login_available?
    end
    with_settings('enabled' => '0') do
      refute controller.oidc_login_available?
    end
  end

  def test_application_controller_patch_exposes_oidc_enabled
    define_stub(:ApplicationController)
    RedmineOidc::Hooks.install!

    assert_includes ApplicationController.ancestors, RedmineOidc::Patches::ApplicationControllerPatch
    with_settings('enabled' => '1', 'issuer' => 'https://idp', 'client_id' => 'c') do
      assert ApplicationController.new.oidc_enabled?
    end
  end

  def test_user_patch_defines_oidc_user_predicate
    # Mirrors the ActiveRecord column Redmine adds via the plugin migration.
    define_stub(:User) { attr_accessor :oidc_subject }
    RedmineOidc::Hooks.install!

    assert_includes User.ancestors, RedmineOidc::Patches::UserPatch
    user = User.new
    refute user.oidc_user?
    user.oidc_subject = 'sub-1'
    assert user.oidc_user?
  end

  def test_install_returns_true_when_patches_are_applied
    define_stub(:ApplicationController)
    assert RedmineOidc::Hooks.install!
  end

  def test_install_returns_false_without_redmine_constants
    refute RedmineOidc::Hooks.install!
  end
end
