# frozen_string_literal: true

require_relative 'redmine_oidc/settings'
require_relative 'redmine_oidc/settings_form'
require_relative 'redmine_oidc/discovery'
require_relative 'redmine_oidc/token_response'
require_relative 'redmine_oidc/id_token'
require_relative 'redmine_oidc/client'
require_relative 'redmine_oidc/claims'
require_relative 'redmine_oidc/synchronizer'
require_relative 'redmine_oidc/connectivity'
require_relative '../app/controllers/redmine_oidc/callback_url'
require_relative 'redmine_oidc/view_helper'
require_relative 'redmine_oidc/hooks'
require_relative 'redmine_oidc/patches/account_patch'
require_relative 'redmine_oidc/patches/application_controller_patch'
require_relative 'redmine_oidc/patches/user_patch'

module RedmineOidc
  # Installs the plugin into Redmine's extension points.
  #
  # Guarded so the library stays loadable outside a Rails boot (unit tests,
  # static analysis) where the patched constants do not exist yet.
  def self.install!
    Hooks.install!
  end
end

RedmineOidc.install! if defined?(Redmine::Plugin)
