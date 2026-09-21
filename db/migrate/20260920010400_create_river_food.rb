# frozen_string_literal: true
class CreateRiverFood < ActiveRecord::Migration[7.2]
  def change
    create_table :river_food_commands do |t|
      t.bigint :user_id, null: false
      t.string :key, null: false
      t.string :fingerprint, null: false
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end
    add_index :river_food_commands, [:user_id, :key], unique: true
    create_table :river_food_events do |t|
      t.bigint :user_id, null: false
      t.string :key, null: false
      t.string :text, null: false
      t.string :path, null: false
      t.bigint :notification_id
      t.timestamps
    end
    add_index :river_food_events, :key, unique: true
    create_table :river_food_audits do |t|
      t.bigint :user_id, null: false
      t.string :action, null: false
      t.string :target_kind
      t.bigint :target_id
      t.string :reason, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    create_table :river_food_legacies do |t|
      t.string :source, null: false
      t.string :legacy_id, null: false
      t.string :target_kind
      t.bigint :target_id
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :river_food_legacies, [:source, :legacy_id], unique: true
    create_table :river_food_media do |t|
      t.bigint :user_id, null: false
      t.string :token, null: false
      t.binary :bytes, null: false
      t.integer :size, null: false
      t.timestamps
    end
    add_index :river_food_media, :token, unique: true
    create_table :river_food_reactions do |t|
      t.bigint :user_id, null: false
      t.string :target_kind, null: false
      t.bigint :target_id, null: false
      t.integer :value, null: false
      t.timestamps
    end
    add_index :river_food_reactions, [:user_id, :target_kind, :target_id], unique: true, name: 'river_food_reaction_unique'
    add_check_constraint :river_food_reactions, 'value IN (-1,1)', name: 'river_food_reaction_value'
    create_table :river_food_reports do |t|
      t.bigint :user_id, null: false
      t.string :target_kind, null: false
      t.bigint :target_id, null: false
      t.string :reason, null: false
      t.datetime :handled_at
      t.timestamps
    end
    add_index :river_food_reports, [:user_id, :target_kind, :target_id], unique: true, name: 'river_food_report_unique'
    create_table :river_food_comments do |t|
      t.bigint :user_id, null: false
      t.string :target_kind, null: false
      t.bigint :target_id, null: false
      t.bigint :parent_id
      t.text :body, null: false
      t.boolean :anonymous, null: false, default: false
      t.string :status, null: false, default: 'visible'
      t.decimal :rating, precision: 3, scale: 1
      t.jsonb :media_ids, null: false, default: []
      t.timestamps
    end
    add_index :river_food_comments, [:target_kind, :target_id, :id], name: 'river_food_comment_target'
    add_foreign_key :river_food_comments, :river_food_comments, column: :parent_id
    add_check_constraint :river_food_comments, 'rating IS NULL OR (rating >= 0.5 AND rating <= 5)', name: 'river_food_comment_rating'
    create_table :river_food_shops do |t|
      t.bigint :user_id
      t.string :name, null:false
      t.string :area, null:false
      t.string :category
      t.string :status, null:false, default:'visible'
      t.string :business_status, null:false, default:'open'
      t.string :status_reason
      t.integer :lock_version, null:false, default:0
      t.text :body
      t.decimal :base_rating, precision:3, scale:1
      t.jsonb :details, null:false, default:{}
      t.jsonb :media_ids, null:false, default:[]
      t.timestamps
    end
    create_table :river_food_dishes do |t|
      t.bigint :shop_id, null:false
      t.bigint :user_id
      t.string :name, null:false
      t.text :body
      t.decimal :price, precision:12, scale:2
      t.string :status, null:false, default:'visible'
      t.jsonb :media_ids, null:false, default:[]
      t.timestamps
    end
    add_foreign_key :river_food_dishes, :river_food_shops, column: :shop_id
    create_table :river_food_proposals do |t|
      t.bigint :user_id
      t.bigint :shop_id
      t.bigint :reviewer_id
      t.integer :base_version
      t.string :status, null:false, default:'pending'
      t.string :reason
      t.jsonb :before_snapshot, null:false, default:{}
      t.jsonb :proposed_changes, null:false, default:{}
      t.timestamps
    end
    add_foreign_key :river_food_proposals, :river_food_shops, column: :shop_id
    create_table :river_food_favorites do |t|
      t.bigint :user_id, null:false
      t.bigint :shop_id, null:false
      t.timestamps
    end
    add_index :river_food_favorites, [:user_id,:shop_id], unique:true
    add_foreign_key :river_food_favorites, :river_food_shops, column: :shop_id
    create_table :river_food_about_pages do |t|
      t.bigint :user_id
      t.text :body, null:false
      t.string :status, null:false, default:'visible'
      t.timestamps
    end
  end
end
