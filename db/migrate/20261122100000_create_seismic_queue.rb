# frozen_string_literal: true

# Job queue for the damage-detection worker. The queue lives in the database
# (no extra broker): Rails inserts rows, an external low-priority Python
# worker claims them with SELECT ... FOR UPDATE SKIP LOCKED.
class CreateSeismicQueue < ActiveRecord::Migration[7.0]
  def change
    create_table :seismic_jobs do |t|
      t.references :project, null: false, foreign_key: true, index: true
      t.references :document, null: true, foreign_key: { on_delete: :nullify }, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.string :status, null: false, default: "queued" # queued running done failed cancelled
      t.integer :priority, null: false, default: 0     # higher is claimed first
      t.jsonb :params, null: false, default: {}
      t.integer :total_images, null: false, default: 0
      t.integer :done_images, null: false, default: 0
      t.integer :failed_images, null: false, default: 0
      t.string :output_dir
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :seismic_jobs, %i[status priority id]

    create_table :seismic_image_results do |t|
      t.references :seismic_job, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :attachment, null: true, foreign_key: { on_delete: :nullify }, index: true
      t.string :filename, null: false
      t.string :source_path
      t.string :digest
      t.string :status, null: false, default: "queued" # queued running done failed cancelled
      t.jsonb :detections, null: false, default: []
      t.jsonb :summary, null: false, default: {}
      t.integer :width
      t.integer :height
      t.string :overlay_path
      t.string :mask_path
      t.text :error
      t.integer :duration_ms
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :seismic_image_results, %i[status seismic_job_id id], name: "idx_seismic_results_claim"
    add_index :seismic_image_results, :digest

    create_table :seismic_worker_status do |t|
      t.string :name, null: false
      t.datetime :beat_at, null: false
      t.bigint :current_job_id
      t.jsonb :info, null: false, default: {}
    end
    add_index :seismic_worker_status, :name, unique: true
  end
end
