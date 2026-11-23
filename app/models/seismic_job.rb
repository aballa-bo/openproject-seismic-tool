# frozen_string_literal: true

class SeismicJob < ApplicationRecord
  STATUSES = %w[queued running done failed cancelled].freeze
  ACTIVE = %w[queued running].freeze

  DEFAULT_PARAMS = {
    "mode" => "cascade",   # cascade: detector + crack segmentation | detector | crack_only
    "conf" => 0.25,        # detector confidence
    "crack_conf" => 0.25,  # crack segmentation confidence
    "imgsz" => 1280
  }.freeze

  belongs_to :project
  belongs_to :document, optional: true
  belongs_to :user
  has_many :seismic_image_results, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(id: :desc) }
  scope :active, -> { where(status: ACTIVE) }

  def active? = ACTIVE.include?(status)

  def progress_percent
    return 0 if total_images.zero?

    ((done_images + failed_images) * 100.0 / total_images).round
  end

  def cancel!
    transaction do
      seismic_image_results.where(status: "queued").update_all(status: "cancelled", updated_at: Time.current)
      update!(status: "cancelled", finished_at: Time.current)
    end
  end

  # Re-queue the images that failed or were cancelled.
  def retry!
    transaction do
      seismic_image_results.where(status: %w[failed cancelled])
                           .update_all(status: "queued", error: nil, updated_at: Time.current)
      update!(status: "queued", finished_at: nil, error: nil,
              failed_images: 0,
              done_images: seismic_image_results.where(status: "done").count)
    end
  end

  def self.worker_alive?
    row = ActiveRecord::Base.connection.select_one(
      "SELECT beat_at FROM seismic_worker_status ORDER BY beat_at DESC LIMIT 1"
    )
    row && Time.zone.parse(row["beat_at"].to_s) > 2.minutes.ago
  rescue StandardError
    false
  end

  # Message explaining why a queued job is not moving, or nil.
  def self.worker_hint
    row = ActiveRecord::Base.connection.select_one(
      "SELECT beat_at, info FROM seismic_worker_status ORDER BY beat_at DESC LIMIT 1"
    )
    return "The analysis worker is not running: jobs stay queued until the openproject-seismic-worker service is started." unless
      row && Time.zone.parse(row["beat_at"].to_s) > 2.minutes.ago

    raw = row["info"]
    info = raw.is_a?(Hash) ? raw : (JSON.parse(raw.to_s) rescue {})
    return nil unless info["state"] == "waiting_load"

    "The worker is waiting: the server is busy (load #{info['load_per_core']} per core, limit #{info['limit']}). " \
      "It starts by itself when the load drops."
  rescue StandardError
    nil
  end

  # Folder (under the attachments storage) that holds a job's output images.
  def self.storage_root
    base = OpenProject::Configuration.attachments_storage_path.to_s
    Pathname.new(base).join("seismic_tool")
  end

  before_destroy :remove_output

  private

  def remove_output
    return if output_dir.blank?

    dir = Pathname.new(output_dir)
    FileUtils.rm_rf(dir) if dir.to_s.start_with?(self.class.storage_root.to_s)
  end
end
