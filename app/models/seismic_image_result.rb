# frozen_string_literal: true

class SeismicImageResult < ApplicationRecord
  belongs_to :seismic_job
  belongs_to :attachment, optional: true

  scope :done, -> { where(status: "done") }

  def crack_count = summary.to_h.fetch("Cracks", 0)

  def classes_found
    summary.to_h.reject { |_k, v| v.to_i.zero? }
  end

  # Detections are stored as an array of hashes:
  # { "class", "confidence", "box": [x1,y1,x2,y2], "area_px", "length_px", "mean_width_px" }
  def cracks
    detections.to_a.select { |d| d["class"] == "Cracks" }
  end
end
