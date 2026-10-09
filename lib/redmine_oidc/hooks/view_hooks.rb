# frozen_string_literal: true

module RedmineOidc
  module Hooks
    # Injects OIDC UI fragments (account menu entry, login form hooks).
    class ViewHooks < Redmine::Hook::ViewListener
      render_on :view_account_login_auth_provider,
                partial: 'redmine_oidc/hooks/login_button'
    end
  end
end
