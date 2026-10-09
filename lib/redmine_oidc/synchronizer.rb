# frozen_string_literal: true

module RedmineOidc
  # Turns verified OIDC claims into a Redmine user session.
  #
  # Lookup order is deterministic and never silently creates duplicates:
  #   1. an existing `oidc_subject` binding
  #   2. an existing account matching the provider login
  #   3. an existing account matching the verified email
  #   4. a freshly created account (only when auto-creation is enabled)
  class Synchronizer
    class Error < StandardError; end

    Result = Struct.new(:user, :created, keyword_init: true)

    def initialize(claims, source: self.class.name)
      @claims = claims.is_a?(Claims) ? claims : Claims.new(claims)
      @source = source
    end

    # @return [Result]
    def call
      raise Error, I18n.t(:error_oidc_missing_subject) if @claims.subject.blank?

      user = find_bound_user || find_by_login || find_by_email || create_user
      raise Error, I18n.t(:error_oidc_user_not_allowed) if user.nil?

      update_user(user)
      user.activate! if user.respond_to?(:activate!) && !user.active?
      Result.new(user: user, created: user.previously_new_record?)
    end

    private

    def find_bound_user
      User.find_by(oidc_subject: @claims.subject)
    end

    def find_by_login
      return nil if @claims.login.blank?

      User.find_by(login: @claims.login)
    end

    def find_by_email
      return nil if @claims.email.blank?

      User.find_by_mail(@claims.email)
    end

    def create_user
      return nil unless Settings.auto_create_user?

      user = User.new(
        login: available_login,
        firstname: @claims.firstname.presence || @claims.login,
        lastname: @claims.lastname.presence || 'OIDC',
        mail: @claims.email.presence || generated_mail,
        language: Setting.default_language
      )
      user.oidc_subject = @claims.subject
      user.password = SecureRandom.hex(32)

      unless user.save
        raise Error, "#{I18n.t(:error_oidc_user_creation_failed)}: #{user.errors.full_messages.join(', ')}"
      end

      assign_default_roles(user)
      user
    end

    def update_user(user)
      attributes = { oidc_subject: @claims.subject }
      if Settings.update_user_attributes?
        attributes[:firstname] = @claims.firstname if @claims.firstname.present?
        attributes[:lastname] = @claims.lastname if @claims.lastname.present?
        attributes[:mail] = @claims.email if @claims.email.present? && user.mail.blank?
      end

      user.update_columns(attributes) if user.oidc_subject != @claims.subject || attributes.size > 1
      apply_admin_group(user)
    end

    # Promotes the account to administrator only when the provider marks it as
    # an admin *and* the configured group matches its system name. The group
    # setting is the explicit opt-in that prevents an external provider from
    # silently granting Redmine admin rights.
    def apply_admin_group(user, group = Settings['admin_group'].to_s.strip)
      return if user.nil? || group.blank?
      return unless @claims.system_admin? || @claims.system_role == 'admin'
      return unless group.to_s.casecmp(@claims.system_name.to_s).zero? ||
                    group.to_s.casecmp('admin').zero?
      return if user.admin?

      user.admin = true
      user.save(validate: false)
    end

    def assign_default_roles(user)
      role_ids = Settings.default_role_ids
      role_ids = [Role.default.id] if role_ids.empty? && Role.default
      user.role_ids = role_ids.compact.uniq
    end

    # Redmine login rules: lowercase alphanumeric, dash, underscore, at sign, dot.
    def available_login
      base = @claims.login.to_s.gsub(/[^a-z0-9\-_.@]/i, '').presence || "oidc#{SecureRandom.hex(4)}"
      candidate = base
      suffix = 1
      while User.where(login: candidate).exists?
        candidate = "#{base}#{suffix}"
        suffix += 1
      end
      candidate
    end

    def generated_mail
      "#{available_login}@oidc.local"
    end
  end
end
