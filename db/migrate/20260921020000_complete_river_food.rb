# frozen_string_literal: true
class CompleteRiverFood < ActiveRecord::Migration[7.2]
  def change
    add_column :river_food_shops, :review, :text
    add_column :river_food_shops, :missing_media_count, :integer, default: 0, null: false
    add_column :river_food_comments, :tags, :jsonb, default: [], null: false
    add_column :river_food_comments, :missing_media_count, :integer, default: 0, null: false
    add_column :river_food_dishes, :tag, :string
    add_column :river_food_dishes, :missing_media_count, :integer, default: 0, null: false
    add_column :river_food_proposals, :review_reason, :text
    add_column :river_food_proposals, :reviewed_at, :datetime
    add_column :river_food_proposals, :missing_media_count, :integer, default: 0, null: false
    create_table :river_food_historical_identities do |t|
      t.string :legacy_id, null: false
      t.bigint :virtual_user_id, null: false
      t.string :username, null: false
      t.bigint :linked_user_id
      t.timestamps
    end
    add_index :river_food_historical_identities, :legacy_id, unique: true
    add_index :river_food_historical_identities, :virtual_user_id, unique: true
    add_index :river_food_comments, [:target_kind, :target_id, :status, :created_at], name: 'river_food_comment_visible'
    add_index :river_food_proposals, [:status, :created_at]
    add_index :river_food_shops, [:status, :area]
  end
end
