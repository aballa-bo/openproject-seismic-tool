# frozen_string_literal: true

class AedesForm < ApplicationRecord
  STATUSES = %w[draft final].freeze

  belongs_to :project
  belongs_to :author, class_name: "User"

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  validates :form_type, inclusion: { in: ->(_) { SeismicTool::Forms::TYPES.keys } }

  def schema = SeismicTool::Forms.schema(form_type)

  def value(key) = data.to_h[key.to_s]
end
