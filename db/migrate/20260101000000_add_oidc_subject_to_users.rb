# frozen_string_literal: true

class AddOidcSubjectToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :oidc_subject, :string, limit: 255 unless column_exists?(:users, :oidc_subject)
    add_index :users, :oidc_subject, unique: true unless index_exists?(:users, :oidc_subject)
  end
end
