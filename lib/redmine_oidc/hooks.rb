# frozen_string_literal: true

module RedmineOidc
  # Wires the plugin into Redmine's extension points.
  module Hooks
    # @return [Boolean] whether any patch was applied
    def self.install!
      applied = false

      if defined?(::AccountController)
        ::AccountController.include(RedmineOidc::Patches::AccountPatch)
        applied = true
      end

      if defined?(::ApplicationController)
        ::ApplicationController.include(RedmineOidc::Patches::ApplicationControllerPatch)
        applied = true
      end

      if defined?(::User)
        ::User.include(RedmineOidc::Patches::UserPatch)
        applied = true
      end

      require_relative 'hooks/view_hooks' if defined?(::Redmine::Hook::ViewListener)
      applied
    end
  end
end
