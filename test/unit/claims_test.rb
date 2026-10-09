# frozen_string_literal: true

require_relative '../test_helper'

class ClaimsTest < Minitest::Test
  def test_prefers_sub_as_subject
    claims = RedmineOidc::Claims.new('sub' => 'user-1', 'preferred_username' => 'alice')
    assert_equal 'user-1', claims.subject
  end

  def test_falls_back_to_preferred_username_then_email
    assert_equal 'alice', RedmineOidc::Claims.new('preferred_username' => 'alice').subject
    assert_equal 'a@example.com', RedmineOidc::Claims.new('email' => 'a@example.com').subject
  end

  def test_login_is_downcased_and_trimmed
    claims = RedmineOidc::Claims.new('preferred_username' => '  Alice  ')
    assert_equal 'alice', claims.login
  end

  def test_strips_whitespace_from_string_claims
    claims = RedmineOidc::Claims.new('email' => '  user@example.com  ')
    assert_equal 'user@example.com', claims.email
  end

  def test_uses_explicit_given_and_family_names
    claims = RedmineOidc::Claims.new('given_name' => 'Ada', 'family_name' => 'Lovelace')
    assert_equal 'Ada', claims.firstname
    assert_equal 'Lovelace', claims.lastname
  end

  def test_splits_display_name_when_parts_are_missing
    claims = RedmineOidc::Claims.new('name' => 'Ada Lovelace')
    assert_equal 'Ada', claims.firstname
    assert_equal 'Lovelace', claims.lastname
  end

  def test_single_word_name_leaves_lastname_nil
    claims = RedmineOidc::Claims.new('name' => 'Prince')
    assert_equal 'Prince', claims.firstname
    assert_nil claims.lastname
  end

  def test_marks_claim_set_as_managed_when_permission_keys_exist
    assert RedmineOidc::Claims.new('system_permissions' => []).managed?
    assert RedmineOidc::Claims.new('system_pages' => []).managed?
    refute RedmineOidc::Claims.new({}).managed?
  end

  def test_empty_array_is_distinct_from_missing_permissions
    managed = RedmineOidc::Claims.new('system_permissions' => [])
    assert_empty managed.system_permissions
    assert managed.managed?
  end

  def test_detects_system_admin
    assert RedmineOidc::Claims.new('system_admin' => true).system_admin?
    refute RedmineOidc::Claims.new('system_admin' => 'true').system_admin?
  end

  def test_email_verified_requires_explicit_true
    assert RedmineOidc::Claims.new('email_verified' => true).email_verified?
    refute RedmineOidc::Claims.new('email_verified' => false).email_verified?
    refute RedmineOidc::Claims.new({}).email_verified?
  end

  def test_handles_non_hash_input_gracefully
    claims = RedmineOidc::Claims.new(nil)
    assert_nil claims.subject
    refute claims.managed?
  end

  # SADP claims permissions through role assignment and then omits
  # `system_name`, exposing only `oidc_roles` (see OAuth2ServerConfig
  # `claimRolePermissions`). Claims must surface those role names.
  def test_reads_role_names_from_oidc_roles
    claims = RedmineOidc::Claims.new('oidc_roles' => ['Redmine Admin', ' Auditor '])
    assert_equal ['Redmine Admin', 'Auditor'], claims.role_names
  end

  def test_role_names_ignore_blank_and_non_string_entries
    claims = RedmineOidc::Claims.new('oidc_roles' => ['  ', nil, 42, 'Ops'])
    assert_equal ['Ops'], claims.role_names
  end

  def test_group_names_combines_system_name_and_roles
    claims = RedmineOidc::Claims.new('system_name' => 'Redmine', 'oidc_roles' => ['Redmine Admin'])
    assert_equal ['Redmine', 'Redmine Admin'], claims.group_names
  end

  def test_group_names_is_empty_without_system_name_or_roles
    assert_empty RedmineOidc::Claims.new({}).group_names
  end
end
