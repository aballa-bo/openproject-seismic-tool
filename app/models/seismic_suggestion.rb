# frozen_string_literal: true

class SeismicSuggestion < ApplicationRecord
  STATUSES = %w[pending confirmed rejected].freeze

  belongs_to :project
  belongs_to :seismic_image_result
  belongs_to :work_package, optional: true
  belongs_to :decided_by, class_name: "User", optional: true

  validates :kind, inclusion: { in: %w[structural non_structural] }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }

  def structural? = kind == "structural"
  def box = detail.to_h["box"]
end
