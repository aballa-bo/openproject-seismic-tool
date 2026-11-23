# frozen_string_literal: true

# One single-image 3D reconstruction (Crack modelling section).
class SeismicModelJob < ApplicationRecord
  STATUSES = %w[queued running done failed cancelled].freeze
  ACTIVE = %w[queued running].freeze

  DEFAULT_PARAMS = {
    "highlight_cracks" => true, # tint crack pixels red (needs the crack segmentation weights)
    "groove" => 0.04,           # engrave the cracks into the surface (0 = off)
    "crack_conf" => 0.25,
    "max_points" => 250_000,
    "mesh_side" => 320,         # mesh resolution (longer side, in vertices)
    "max_side" => 1024          # input image is reduced to this size
  }.freeze

  # downloadable / viewable outputs: key => [file name, content type]
  FILES = {
    "pointcloud" => ["pointcloud.ply", "application/octet-stream"],
    "mesh_ply" => ["mesh.ply", "application/octet-stream"],
    "mesh_obj" => ["mesh.obj", "text/plain"],
    "depth" => ["depth.png", "image/png"],
    "input" => ["input.jpg", "image/jpeg"]
  }.freeze

  belongs_to :project
  belongs_to :user
  belongs_to :attachment, optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(id: :desc) }

  def active? = ACTIVE.include?(status)
  def done? = status == "done"

  def cancel!
    update!(status: "cancelled", finished_at: Time.current) if active?
  end

  def retry!
    update!(status: "queued", error: nil, finished_at: nil, started_at: nil, stats: {})
  end

  def file_path(key)
    name, = FILES[key]
    return nil unless name && output_dir.present?

    path = File.join(output_dir, name)
    File.file?(path) ? path : nil
  end

  before_destroy :remove_output

  private

  def remove_output
    return if output_dir.blank?

    dir = Pathname.new(output_dir)
    FileUtils.rm_rf(dir) if dir.to_s.start_with?(SeismicJob.storage_root.to_s)
  end
end
