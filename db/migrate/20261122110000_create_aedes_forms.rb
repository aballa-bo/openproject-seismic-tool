# frozen_string_literal: true

class CreateAedesForms < ActiveRecord::Migration[7.0]
  def change
    create_table :aedes_forms do |t|
      t.references :project, null: false, foreign_key: true, index: true
      t.references :author, null: false, foreign_key: { to_table: :users }, index: true
      t.string :title, null: false
      t.string :form_type, null: false, default: "a_dc" # a_dc (churches, MiBAC 2006) | gl_aedes
      t.string :status, null: false, default: "draft" # draft final
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
  end
end
