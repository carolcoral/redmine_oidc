# frozen_string_literal: true

# Handles the OIDC authorization-code flow for Redmine.
#
# The controller is intentionally thin: state handling, token exchange and user
# provisioning all live in `RedmineOidc::*` so they can be unit-tested without a
# browser. Only the HTTP concerns (redirect, session, error rendering) are here.
class RedmineOidcController < ApplicationController
  include Redmine::I18n

  skip_before_action :check_if_login_required, only: %i[login callback failure]
  skip_before_action :verify_authenticity_token, only: %i[callback]
  before_action :require_oidc_enabled
  before_action :set_locale, only: %i[login callback failure]

  # GET /oidc/login — starts the authorization code flow.
  def login
    state = RedmineOidc::Client.generate_token
    nonce = RedmineOidc::Client.generate_token
    store_flow(state: state, nonce: nonce, back_url: params[:back_url])

    redirect_to client.authorization_url(
      redirect_uri: callback_url,
      state: state,
      nonce: nonce
    ), allow_other_host: true
  rescue RedmineOidc::Discovery::Error => e
    render_failure(e.message)
  end

  # GET /oidc/callback — validates state, exchanges the code and signs the user in.
  def callback
    error = params[:error]
    return render_failure(params[:error_description].presence || error) if error.present?

    unless valid_state?(params[:state])
      return render_failure(I18n.t(:error_oidc_invalid_state))
    end

    code = params[:code]
    return render_failure(I18n.t(:error_oidc_missing_code)) if code.blank?

    token = client.exchange_code(code: code, redirect_uri: callback_url)
    claims = client.verify_id_token(token.id_token, nonce: session[:oidc_nonce])
    userinfo = fetch_userinfo(token)
    claims = claims.merge(userinfo) if userinfo.is_a?(Hash)

    result = RedmineOidc::Synchronizer.new(claims).call
    sign_in_user(result.user, id_token: token.id_token)
    redirect_to_success
  rescue RedmineOidc::Client::Error, RedmineOidc::IdToken::Error,
         RedmineOidc::Discovery::Error, RedmineOidc::Synchronizer::Error => e
    Rails.logger.warn "[redmine_oidc] Login failed: #{e.message}"
    render_failure(e.message)
  ensure
    clear_flow
  end

  # GET /oidc/logout — clears the local session and, when the provider supports
  # it, redirects to the end-session endpoint (RP-initiated logout).
  def logout
    id_token = session[:oidc_id_token]
    self.logged_user = nil
    session.delete(:user_id)
    session.delete(:oidc_id_token)
    session.delete(:oidc_subject)

    url = end_session_url(id_token)
    if url.present?
      redirect_to url, allow_other_host: true
    else
      redirect_to home_url
    end
  end

  # GET /oidc/failure — friendly error page.
  def failure
    render_failure(params[:message].presence || I18n.t(:error_oidc_login_failed))
  end

  private

  def client
    @client ||= RedmineOidc::Client.new
  end

  def fetch_userinfo(token)
    return nil if token.access_token.blank?

    client.userinfo(token.access_token)
  rescue RedmineOidc::Client::Error => e
    Rails.logger.warn "[redmine_oidc] userinfo lookup failed: #{e.message}"
    nil
  end

  # Establishes the Redmine session for a provisioned user.
  #
  # The session is rebuilt rather than extended: `logged_user=` refreshes the
  # Rails session id, which prevents session fixation when a user's privileges
  # change as part of signing in.
  def sign_in_user(user, id_token: nil)
    return if user.nil?

    user.update_column(:last_login_on, Time.now) if user.respond_to?(:last_login_on)
    self.logged_user = user

    session[:oidc_subject] = user.oidc_subject
    # Kept so RP-initiated logout can send id_token_hint to the provider.
    session[:oidc_id_token] = id_token
    session[:oidc_logged_in_at] = Time.now.to_i
  end

  def redirect_to_success
    back_url = session.delete(:oidc_back_url)
    redirect_to(back_url.presence || home_url, allow_other_host: false)
  end

  def require_oidc_enabled
    return if RedmineOidc::Settings.enabled?

    render_failure(I18n.t(:error_oidc_disabled), status: :forbidden)
  end

  def end_session_url(id_token)
    return nil unless RedmineOidc::Settings.end_session_enabled?

    client.end_session_url(id_token_hint: id_token, post_logout_redirect_uri: home_url)
  end

  def store_flow(state:, nonce:, back_url:)
    session[:oidc_state] = state
    session[:oidc_nonce] = nonce
    session[:oidc_back_url] = sanitized_back_url(back_url)
  end

  # Drops the one-shot flow values. The id_token is deliberately kept: it is
  # needed later for RP-initiated logout.
  def clear_flow
    session.delete(:oidc_state)
    session.delete(:oidc_nonce)
    session.delete(:oidc_back_url)
  end

  def valid_state?(state)
    expected = session[:oidc_state]
    expected.present? && state.present? && ActiveSupport::SecurityUtils.secure_compare(expected.to_s, state.to_s)
  end

  # Only allow same-host relative paths to avoid open redirects.
  def sanitized_back_url(back_url)
    return nil if back_url.blank?

    uri = URI.parse(back_url)
    return nil if uri.host.present?

    back_url.start_with?('/') ? back_url : nil
  rescue URI::InvalidURIError
    nil
  end

  def render_failure(message, status: :unprocessable_entity)
    @message = message
    render template: 'redmine_oidc/failure', status: status, layout: 'base'
  end

  def callback_url
    RedmineOidc::CallbackUrl.build(request)
  end
end
