# frozen_string_literal: true

# A suggestion is one detection from the image analysis waiting for a human
# decision: confirmed -> an AeDES work package is created from it,
# rejected -> dismissed.
class CreateSeismicSuggestions < ActiveRecord::Migration[7.0]
  def change
    create_table :seismic_suggestions do |t|
      t.references :project, null: false, foreign_key: true, index: true
      t.references :seismic_image_result, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.integer :detection_index, null: false
      t.string :kind, null: false                       # structural | non_structural
      t.string :damage_class, null: false               # MSD-Det class
      t.float :confidence
      t.jsonb :detail, null: false, default: {}         # box, crack stats
      t.string :status, null: false, default: "pending" # pending confirmed rejected
      t.references :work_package, null: true, foreign_key: { on_delete: :nullify }, index: true
      t.references :decided_by, null: true, foreign_key: { to_table: :users }
      t.datetime :decided_at
      t.timestamps
    end
    add_index :seismic_suggestions, %i[seismic_image_result_id detection_index], unique: true,
                                                                                  name: "idx_seismic_suggestion_unique"
  end
end
