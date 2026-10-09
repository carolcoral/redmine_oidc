# frozen_string_literal: true

require_relative '../test_helper'

# The view hook is a thin declaration; this test pins its target so a typo in
# the hook name or partial path cannot silently break the login button.
class ViewHooksTest < Minitest::Test
  REGISTRATIONS = []

  class FakeViewListener
    def self.render_on(hook, options = {})
      REGISTRATIONS << { hook: hook, options: options }
    end
  end

  def setup
    @original = Object.const_get(:Redmine) if Object.const_defined?(:Redmine)
    Object.send(:remove_const, :Redmine) if Object.const_defined?(:Redmine)
    redmine = Module.new
    redmine.const_set(:Hook, Module.new)
    redmine.const_get(:Hook).const_set(:ViewListener, FakeViewListener)
    Object.const_set(:Redmine, redmine)
  end

  def teardown
    Object.send(:remove_const, :Redmine)
    Object.const_set(:Redmine, @original) if @original
  end

  def load_hook
    # Reload against the freshly stubbed ViewListener base class. The module is
    # removed first so the class body (and its render_on call) executes again.
    if RedmineOidc.const_defined?(:Hooks) && RedmineOidc::Hooks.const_defined?(:ViewHooks)
      RedmineOidc::Hooks.send(:remove_const, :ViewHooks)
    end
    REGISTRATIONS.clear
    load '/workspace/lib/redmine_oidc/hooks/view_hooks.rb'
  end

  def test_registers_the_login_button_partial
    load_hook
    assert_equal 1, REGISTRATIONS.size
    registration = REGISTRATIONS.first
    assert_equal :view_account_login_auth_provider, registration[:hook]
    assert_equal 'redmine_oidc/hooks/login_button', registration[:options][:partial]
  end
end
