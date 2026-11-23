# frozen_string_literal: true

class AddPublishedAtToSeismicImageResults < ActiveRecord::Migration[7.0]
  def change
    add_column :seismic_image_results, :published_at, :datetime
  end
end
