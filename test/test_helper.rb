# frozen_string_literal: true

# Minimal test harness.
#
# The full Redmine test suite requires a Rails environment and a database, which
# is impractical inside the plugin repository alone. These unit tests instead
# exercise the pure-Ruby logic (claims mapping, ID token verification, discovery,
# callback URL building) with lightweight stubs for the handful of Rails APIs
# the code touches.
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'json'
require 'base64'
require 'openssl'
begin
  require 'webmock/minitest'
rescue LoadError
  nil
end

# --- Rails / ActiveSupport shims -------------------------------------------------
module Rails
  def self.cache
    @cache ||= MemoryCache.new
  end

  def self.logger
    @logger ||= Logger.new(IO::NULL)
  end

  def self.root
    Pathname.new(File.expand_path('..', __dir__))
  end

  class MemoryCache
    def initialize
      @store = {}
    end

    def read(key)
      entry = @store[key]
      return nil if entry.nil?

      value, expires_at = entry
      if expires_at && Time.now > expires_at
        @store.delete(key)
        return nil
      end
      value
    end

    def write(key, value, **options)
      ttl = options[:expires_in]
      @store[key] = [value, ttl ? Time.now + ttl : nil]
      value
    end

    def delete(key)
      @store.delete(key)
    end
  end
end

require 'active_support'
require 'active_support/core_ext/object/blank'
require 'active_support/core_ext/string/inflections'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/object/to_query'
require 'active_support/security_utils'
require 'logger'
require 'pathname'
require 'digest'

# --- Plugin under test -----------------------------------------------------------
require 'redmine_oidc'

# Immutable settings used by the test suite.
module TestSettings
  DEFAULTS = {
    'enabled' => '1',
    'issuer' => 'https://idp.example.com',
    'client_id' => 'redmine',
    'client_secret' => 'secret',
    'scopes' => 'openid profile email',
    'button_label' => 'SSO',
    'auto_create_user' => '0',
    'default_role_ids' => [],
    'admin_group' => '',
    'update_user_attributes' => '1',
    'auto_redirect' => '0',
    'end_session_enabled' => '1',
    'verify_ssl' => '1',
    'timeout' => '10',
    'redirect_uri' => ''
  }.freeze
end

module Setting
  # Distinguishes "never set" (defaults) from "explicitly set to nil" so tests
  # can exercise the corrupted-settings path.
  NEVER_SET = Object.new

  class << self
    attr_accessor :stored
  end
  @stored = NEVER_SET

  def self.plugin_redmine_oidc
    stored = @stored
    return TestSettings::DEFAULTS if stored.equal?(NEVER_SET)

    stored
  end

  def self.plugin_redmine_oidc=(value)
    @stored = value
  end

  def self.default_language
    'en'
  end

  def self.method_missing(name, *args)
    nil
  end

  def self.respond_to_missing?(*) = true
end

def with_settings(overrides)
  original = Setting.plugin_redmine_oidc
  Setting.plugin_redmine_oidc = original.merge(overrides.transform_keys(&:to_s))
  yield
ensure
  Setting.plugin_redmine_oidc = original
end

module I18n
  def self.t(key, **options)
    options.empty? ? key.to_s : "#{key}: #{options.values.join(', ')}"
  end
end
