# frozen_string_literal: true

module RedmineOidc
  module Patches
    # Exposes OIDC helpers to every controller/view without touching Redmine core.
    module ApplicationControllerPatch
      def self.included(base)
        base.class_eval do
          helper RedmineOidc::ViewHelper if respond_to?(:helper)
          helper_method :oidc_enabled? if respond_to?(:helper_method)
        end
      end

      def oidc_enabled?
        RedmineOidc::Settings.configured?
      end
    end
  end
end
