# frozen_string_literal: true

module RedmineOidc
  # Admin settings screen: edits plugin settings and offers connectivity checks
  # so misconfiguration is caught before users hit the login flow.
  class SettingsController < ApplicationController
    layout 'admin'
    before_action :require_admin
    before_action :find_plugin

    def show
      @settings = RedmineOidc::Settings.current
      @default_roles = Role.givable.sorted
      @callback_url = RedmineOidc::CallbackUrl.build(request)
    end

    def update
      submitted = params[:settings]
      submitted = submitted.permit(*RedmineOidc::SettingsForm::PERMITTED) if submitted.respond_to?(:permit)
      Setting.plugin_redmine_oidc = RedmineOidc::SettingsForm.merge(submitted)
      flash[:notice] = l(:notice_successful_update)
      redirect_to action: 'show'
    rescue StandardError => e
      Rails.logger.error "[redmine_oidc] Failed to save settings: #{e.message}"
      flash[:error] = e.message
      redirect_to action: 'show'
    end

    # GET /oidc/settings/test — probes discovery + JWKS and reports the result.
    def test
      result = RedmineOidc::Connectivity.report(callback_url: RedmineOidc::CallbackUrl.build(request))

      if result[:success]
        render json: result
      else
        render json: result, status: :unprocessable_entity
      end
    end

    private

    def find_plugin
      @plugin = Redmine::Plugin.find('redmine_oidc')
    rescue Redmine::PluginNotFound
      render_404
    end
  end
end
