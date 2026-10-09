# frozen_string_literal: true

Rails.application.routes.draw do
  get  'oidc/login',    to: 'redmine_oidc#login',    as: 'oidc_login'
  get  'oidc/callback', to: 'redmine_oidc#callback', as: 'oidc_callback'
  get  'oidc/failure',  to: 'redmine_oidc#failure',  as: 'oidc_failure'
  get  'oidc/logout',   to: 'redmine_oidc#logout',   as: 'oidc_logout'

  scope '/admin' do
    get  'oidc/settings',      to: 'redmine_oidc/settings#show',   as: 'redmine_oidc_settings'
    post 'oidc/settings',      to: 'redmine_oidc/settings#update'
    put  'oidc/settings',      to: 'redmine_oidc/settings#update'
    get  'oidc/settings/test', to: 'redmine_oidc/settings#test',   as: 'redmine_oidc_settings_test'
  end
end
