# frozen_string_literal: true

module RedmineOidc
  module Patches
    # Persists the external subject on the user record so the binding survives
    # renames on either side of the integration.
    #
    # The guards keep the patch loadable in isolation (tests, partial boots)
    # where ActiveRecord's `safe_attributes` / `validates` are unavailable.
    module UserPatch
      def self.included(base)
        base.class_eval do
          safe_attributes 'oidc_subject' if respond_to?(:safe_attributes)
          validates :oidc_subject, uniqueness: true, allow_nil: true if respond_to?(:validates)

          include InstanceMethods
        end
      end

      module InstanceMethods
        def oidc_user?
          oidc_subject.present?
        end
      end
    end
  end
end
