# frozen_string_literal: true

module RedmineOidc
  module Patches
    # Hooks the standard login page so the OIDC button appears and, when
    # configured, becomes the only way in for non-administrators.
    #
    # Redmine renders `view_account_login_auth_provider` on its sign-in form,
    # which the plugin's view hook uses to inject the button. Here we additionally
    # guard `login` so the local password form cannot be used to bypass SSO when
    # `hide_local_login` is on.
    module AccountPatch
      def self.included(base)
        base.class_eval do
          helper_method :oidc_login_available? if respond_to?(:helper_method)

          if method_defined?(:login)
            alias_method :login_without_oidc, :login
            alias_method :login, :login_with_oidc
          end
        end
      end

      def oidc_login_available?
        RedmineOidc::Settings.configured?
      end

      # Auto-redirects to the provider when enabled, blocks the local form when
      # `hide_local_login` is set, and otherwise delegates to Redmine unchanged.
      def login_with_oidc
        return redirect_to(oidc_login_path(back_url: params[:back_url])) if auto_redirect?

        if local_login_blocked? && request.post?
          flash.now[:error] = l(:error_oidc_local_login_disabled)
          return render template: 'account/login', layout: 'base'
        end

        respond_to?(:login_without_oidc) ? login_without_oidc : nil
      end

      private

      # `local=1` is the escape hatch so administrators can always reach the
      # password form, e.g. if the provider is down.
      def auto_redirect?
        return false unless oidc_login_available? && RedmineOidc::Settings.auto_redirect?
        return false if params.key?(:local)

        true
      end

      def local_login_blocked?
        return false unless oidc_login_available? && RedmineOidc::Settings.hide_local_login?

        # Administrators keep local login so a provider outage is recoverable.
        user = User.try(:find_by_login, params[:username])
        !(user && user.admin?)
      end

    end
  end
end
