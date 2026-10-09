# frozen_string_literal: true

require_relative '../test_helper'

# Covers the claim -> Redmine user mapping without booting Redmine.
#
# `User` is replaced by an in-memory fake that mimics the small slice of the
# ActiveRecord API the synchronizer relies on, which keeps the test fast while
# still asserting the lookup precedence and update behaviour.
class SynchronizerTest < Minitest::Test
  class FakeUser
    attr_accessor :login, :firstname, :lastname, :mail, :oidc_subject, :admin, :role_ids, :language

    def password=(_value); end

    def initialize(attributes = {})
      attributes.each { |key, value| public_send("#{key}=", value) unless key == :persisted }
      @admin = false
      @errors = FakeErrors.new
      # Mirrors ActiveRecord: true only right after a successful #save of a new row.
      @previously_new_record = false
    end

    def self.repository
      @repository ||= []
    end

    def self.reset!
      @repository = []
    end

    def self.where(conditions)
      matches = repository.select do |user|
        conditions.all? do |key, value|
          user.respond_to?(key) && user.public_send(key) == value
        end
      end
      FakeRelation.new(matches)
    end

    def self.find_by(conditions)
      where(conditions).first
    end

    def self.find_by_mail(mail)
      find_by(mail: mail)
    end

    def self.new(attributes = {})
      fake = allocate
      fake.send(:initialize, attributes)
      repository << fake
      fake
    end

    def save(validate: true)
      return false unless validate ? valid? : true

      @previously_new_record = true
      true
    end

    def valid?
      true
    end

    def previously_new_record?
      @previously_new_record
    end

    def errors
      @errors
    end

    def admin?
      @admin == true
    end

    def active?
      true
    end

    def activate!; end

    def update_columns(attributes)
      attributes.each { |key, value| public_send("#{key}=", value) }
    end

    def update(attributes)
      update_columns(attributes)
      true
    end
  end

  class FakeErrors
    def full_messages
      ['something went wrong']
    end
  end

  class FakeRelation
    include Enumerable

    def initialize(records)
      @records = records
    end

    def each(&block)
      @records.each(&block)
    end

    def exists?
      @records.any?
    end

    def first
      @records.first
    end
  end

  class FakeRole
    attr_reader :id

    def initialize(id, name)
      @id = id
      @name = name
    end

    def self.default
      new(1, 'Anonymous')
    end

    def self.givable
      [new(2, 'Manager')]
    end
  end

  def setup
    FakeUser.reset!
    @original_user = Object.const_get(:User) if Object.const_defined?(:User)
    Object.send(:remove_const, :User) if Object.const_defined?(:User)
    Object.const_set(:User, FakeUser)
    @original_role = Object.const_get(:Role) if Object.const_defined?(:Role)
    Object.send(:remove_const, :Role) if Object.const_defined?(:Role)
    Object.const_set(:Role, FakeRole)
  end

  def teardown
    Object.send(:remove_const, :User)
    Object.send(:remove_const, :Role)
    Object.const_set(:User, @original_user) if @original_user
    Object.const_set(:Role, @original_role) if @original_role
  end

  def claims(overrides = {})
    {
      'sub' => 'user-1',
      'preferred_username' => 'alice',
      'email' => 'alice@example.com',
      'given_name' => 'Alice',
      'family_name' => 'Smith'
    }.merge(overrides)
  end

  def test_binds_an_existing_user_by_subject
    existing = FakeUser.new(login: 'alice', oidc_subject: 'user-1')
    result = RedmineOidc::Synchronizer.new(claims).call

    assert_equal existing, result.user
    refute result.created
  end

  def test_matches_an_existing_user_by_login
    existing = FakeUser.new(login: 'alice')
    result = RedmineOidc::Synchronizer.new(claims).call

    assert_equal existing, result.user
    assert_equal 'user-1', existing.oidc_subject
  end

  def test_matches_an_existing_user_by_email
    existing = FakeUser.new(login: 'someone-else', mail: 'alice@example.com')
    result = RedmineOidc::Synchronizer.new(claims).call

    assert_equal existing, result.user
    assert_equal 'user-1', existing.oidc_subject
  end

  def test_subject_binding_wins_over_login
    bound = FakeUser.new(login: 'renamed', oidc_subject: 'user-1')
    FakeUser.new(login: 'alice')

    assert_equal bound, RedmineOidc::Synchronizer.new(claims).call.user
  end

  def test_refuses_to_create_when_auto_creation_is_disabled
    with_settings('auto_create_user' => '0') do
      assert_raises(RedmineOidc::Synchronizer::Error) do
        RedmineOidc::Synchronizer.new(claims).call
      end
    end
  end

  def test_creates_a_user_when_auto_creation_is_enabled
    with_settings('auto_create_user' => '1') do
      result = RedmineOidc::Synchronizer.new(claims).call

      assert result.created
      assert_equal 'alice', result.user.login
      assert_equal 'Alice', result.user.firstname
      assert_equal 'Smith', result.user.lastname
      assert_equal 'alice@example.com', result.user.mail
      assert_equal 'user-1', result.user.oidc_subject
    end
  end

  def test_sanitizes_unsafe_characters_in_generated_login
    with_settings('auto_create_user' => '1') do
      result = RedmineOidc::Synchronizer.new(claims('preferred_username' => 'Alice <script>')).call
      assert_equal 'alicescript', result.user.login
      assert_match(/\A[a-z0-9\-_.@]+\z/, result.user.login)
    end
  end

  def test_binds_to_the_login_match_even_when_subject_differs
    # Documented precedence: a provider login match wins over creating a new
    # account, so the existing row is (re)bound to the incoming subject.
    existing = FakeUser.new(login: 'alice', oidc_subject: 'someone-else', mail: 'other@example.com')
    with_settings('auto_create_user' => '1') do
      result = RedmineOidc::Synchronizer.new(
        claims('sub' => 'user-2', 'preferred_username' => 'alice', 'email' => 'new@example.com')
      ).call
      assert_equal existing, result.user
      assert_equal 'user-2', result.user.oidc_subject
      refute result.created
    end
  end


  def test_generates_a_local_mail_when_none_is_provided
    with_settings('auto_create_user' => '1') do
      result = RedmineOidc::Synchronizer.new(claims('email' => nil)).call
      assert_equal 'alice@oidc.local', result.user.mail
    end
  end

  def test_requires_a_subject
    error = assert_raises(RedmineOidc::Synchronizer::Error) do
      RedmineOidc::Synchronizer.new({}).call
    end
    assert_match(/subject/, error.message)
  end

  def test_updates_name_from_the_provider
    existing = FakeUser.new(login: 'alice', oidc_subject: 'user-1')
    with_settings('update_user_attributes' => '1') do
      RedmineOidc::Synchronizer.new(claims).call
    end
    assert_equal 'Alice', existing.firstname
  end

  def test_keeps_local_name_when_updates_are_disabled
    existing = FakeUser.new(login: 'alice', oidc_subject: 'user-1', firstname: 'Local')
    with_settings('update_user_attributes' => '0') do
      RedmineOidc::Synchronizer.new(claims).call
    end
    assert_equal 'Local', existing.firstname
  end

  def test_grants_admin_only_for_the_configured_group
    with_settings('admin_group' => 'Redmine', 'auto_create_user' => '1') do
      result = RedmineOidc::Synchronizer.new(
        claims('system_admin' => true, 'system_role' => 'admin', 'system_name' => 'Redmine')
      ).call
      assert result.user.admin?
    end
  end

  def test_does_not_grant_admin_for_an_unlisted_group
    with_settings('admin_group' => 'Redmine', 'auto_create_user' => '1') do
      result = RedmineOidc::Synchronizer.new(
        claims('system_admin' => true, 'system_role' => 'admin', 'system_name' => 'Other')
      ).call
      refute result.user.admin?
    end
  end

  def test_does_not_grant_admin_when_no_group_is_configured
    with_settings('admin_group' => '', 'auto_create_user' => '1') do
      result = RedmineOidc::Synchronizer.new(
        claims('system_admin' => true, 'system_role' => 'admin', 'system_name' => 'Redmine')
      ).call
      refute result.user.admin?
    end
  end

  # SADP's role-based permission path emits `system_admin` / `oidc_roles` but
  # no `system_name`. Matching only against `system_name` would silently
  # disable promotion on that path.
  def test_grants_admin_via_role_name_when_system_name_is_absent
    with_settings('admin_group' => 'Redmine Admin', 'auto_create_user' => '1') do
      result = RedmineOidc::Synchronizer.new(
        claims('system_admin' => true, 'system_role' => 'admin', 'oidc_roles' => ['Redmine Admin'])
      ).call
      assert result.user.admin?
    end
  end

  def test_role_name_matching_is_case_insensitive
    with_settings('admin_group' => 'redmine admin', 'auto_create_user' => '1') do
      result = RedmineOidc::Synchronizer.new(
        claims('system_admin' => true, 'oidc_roles' => ['Redmine Admin'])
      ).call
      assert result.user.admin?
    end
  end

  def test_does_not_grant_admin_for_an_unlisted_role
    with_settings('admin_group' => 'Redmine Admin', 'auto_create_user' => '1') do
      result = RedmineOidc::Synchronizer.new(
        claims('system_admin' => true, 'system_role' => 'admin', 'oidc_roles' => ['Auditor'])
      ).call
      refute result.user.admin?
    end
  end

  def test_does_not_grant_admin_when_role_path_lacks_admin_flag
    with_settings('admin_group' => 'Redmine Admin', 'auto_create_user' => '1') do
      result = RedmineOidc::Synchronizer.new(
        claims('system_role' => 'user', 'oidc_roles' => ['Redmine Admin'])
      ).call
      refute result.user.admin?
    end
  end
end
