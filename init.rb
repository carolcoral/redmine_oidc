# frozen_string_literal: true

require 'redmine'

Redmine::Plugin.register :redmine_oidc do
  name 'Redmine OIDC Plugin'
  author 'carolcoral'
  description 'OpenID Connect (OIDC) single sign-on for Redmine 6.x, compatible with the SADP provider.'
  version '1.0.0'
  url 'https://cnb.cool/xindu.site/redmine_oidc'
  author_url 'https://cnb.cool/xindu.site'

  requires_redmine version_or_higher: '6.0.0'

  settings default: RedmineOidc::Settings::DEFAULTS, partial: 'redmine_oidc/settings/form'

  menu :admin_menu, :redmine_oidc,
       { controller: 'redmine_oidc/settings', action: 'show' },
       caption: :label_redmine_oidc_settings,
       html: { class: 'icon icon-settings' }
end

require_relative 'lib/redmine_oidc'
