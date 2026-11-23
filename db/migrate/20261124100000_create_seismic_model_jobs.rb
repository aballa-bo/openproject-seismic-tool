# frozen_string_literal: true

# Queue for single-image 3D reconstructions ("Crack modelling"), one row per image.
# Processed by the same low-priority worker as the damage-detection queue.
class CreateSeismicModelJobs < ActiveRecord::Migration[7.0]
  def change
    create_table :seismic_model_jobs do |t|
      t.references :project, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.references :attachment, null: true, foreign_key: { on_delete: :nullify }, index: true
      t.string :filename, null: false
      t.string :source_path
      t.string :status, null: false, default: "queued" # queued running done failed cancelled
      t.jsonb :params, null: false, default: {}
      t.jsonb :stats, null: false, default: {}
      t.string :output_dir
      t.text :error
      t.integer :duration_ms
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :seismic_model_jobs, %i[status id]
  end
end
