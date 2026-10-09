# frozen_string_literal: true

module RedmineOidc
  # Normalizes raw OIDC claims into a stable structure the plugin can consume.
  #
  # Providers differ in naming (e.g. `sub` vs `preferred_username`, `name` vs
  # `display_name`), so the mapping lives here instead of being scattered across
  # controllers. The `system_*` claims are SADP-specific permission statements
  # and are carried through for optional role mapping.
  class Claims
    def initialize(raw)
      @raw = raw.is_a?(Hash) ? raw : {}
    end

    attr_reader :raw

    def subject
      value('sub') || value('preferred_username') || value('email')
    end

    def login
      normalize(value('preferred_username') || value('sub') || value('email'))
    end

    def email
      value('email')
    end

    def email_verified?
      raw['email_verified'] == true
    end

    def firstname
      value('given_name') || name_parts.first
    end

    def lastname
      value('family_name') || name_parts.last
    end

    def full_name
      value('name') || [value('given_name'), value('family_name')].compact.join(' ').presence
    end

    # SADP permission statements; absent means "not managed by the platform".
    def system_role
      value('system_role')
    end

    def system_admin?
      raw['system_admin'] == true
    end

    def system_name
      value('system_name')
    end

    # SADP role names carried by the token (`oidc_roles`). When permissions are
    # claimed through role assignment the provider omits `system_name` and only
    # emits the role names, so admin-group matching must consider these too.
    def role_names
      Array(raw['oidc_roles']).filter_map { |role| role.is_a?(String) ? role.strip.presence : nil }
    end

    # Every identifier a configured admin group may match against: the provider
    # system name plus any assigned role names.
    def group_names
      [system_name, *role_names].compact
    end

    def system_permissions
      Array(raw['system_permissions'])
    end

    def managed?
      raw.key?('system_permissions') || raw.key?('system_pages')
    end

    def to_h
      {
        'subject' => subject,
        'login' => login,
        'email' => email,
        'firstname' => firstname,
        'lastname' => lastname,
        'full_name' => full_name,
        'system_role' => system_role,
        'system_admin' => system_admin?,
        'system_name' => system_name,
        'managed' => managed?
      }
    end

    private

    def value(key)
      item = raw[key]
      item.is_a?(String) ? item.strip.presence : item
    end

    def normalize(value)
      value.to_s.strip.downcase.presence
    end

    # Splits the provider display name as a fallback for missing name parts.
    # Kept separate from #firstname / #lastname to avoid mutual recursion.
    def name_parts
      parts = value('name').to_s.split(/\s+/)
      return [nil, nil] if parts.empty?

      [parts.first, parts.length > 1 ? parts.last : nil]
    end
  end
end
