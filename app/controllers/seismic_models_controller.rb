# frozen_string_literal: true

# "Crack modelling": one image in, a 3D relief (point cloud + mesh) out.
class SeismicModelsController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_model, only: %i[show destroy cancel retry file confirm_delete]

  menu_item :seismic_tool
  layout 'base'

  def index
    @models = SeismicModelJob.where(project: @project).includes(:user).recent.limit(100)
  end

  def new
    # documents act as folders: first the list of folders, then the images of the chosen one
    @folders = candidate_images.group_by(&:first).map { |doc, pairs| [doc, pairs.size] }
    @folder = @folders.map(&:first).find { |d| d.id == params[:document_id].to_i }
    @images = @folder ? candidate_images.select { |d, _| d.id == @folder.id } : []
    @params = SeismicModelJob::DEFAULT_PARAMS
    @selected = params[:attachment_id].to_i
  end

  def create
    att = candidate_images.map(&:last).find { |a| a.id == params[:attachment_id].to_i }
    return redirect_to(new_project_seismic_model_path(@project), flash: { error: "Select one image." }) unless att

    path = disk_path(att)
    unless path
      return redirect_to(new_project_seismic_model_path(@project),
                         flash: { error: "The file is not on the local disk (remote storage is not supported)." })
    end

    job = SeismicModelJob.create!(project: @project, user: User.current, attachment: att, filename: att.filename,
                                  source_path: path, params: model_params)
    job.update!(output_dir: SeismicJob.storage_root.join("models", job.id.to_s).to_s)
    flash[:notice] = "3D model queued."
    redirect_to project_seismic_model_path(@project, job)
  end

  def show
    respond_to do |format|
      format.html { @worker_alive = SeismicJob.worker_alive? }
      format.json { render json: model_json(@model) }
    end
  end

  def status
    jobs = SeismicModelJob.where(project: @project).recent.limit(30)
    render json: { jobs: jobs.map { |j| model_json(j) } }
  end

  def cancel
    @model.cancel!
    redirect_to project_seismic_model_path(@project, @model)
  end

  def retry
    @model.retry!
    redirect_to project_seismic_model_path(@project, @model)
  end

  def confirm_delete; end

  def destroy
    @model.destroy
    flash[:notice] = "3D model ##{params[:id]} deleted."
    redirect_to project_seismic_models_path(@project)
  end

  # Serves the generated files (point cloud, mesh, depth map) inline or as a download.
  def file
    path = @model.file_path(params[:kind].to_s)
    return head(:not_found) unless path

    send_file path, disposition: params[:download] == "1" ? "attachment" : "inline",
                    type: SeismicModelJob::FILES[params[:kind].to_s].last
  end

  # Thumbnail source for the image picker (only images attached to this project's documents).
  def source
    att = candidate_images.map(&:last).find { |a| a.id == params[:attachment_id].to_i }
    path = att && disk_path(att)
    return head(:not_found) unless path

    send_file path, disposition: "inline", type: Marcel::MimeType.for(Pathname.new(path))
  end

  private

  def find_model
    @model = SeismicModelJob.where(project: @project).find(params[:id])
  end

  # [[document, attachment], ...] for every image attached to a document of the project
  def candidate_images
    @candidate_images ||= @project.documents.includes(:attachments).order(created_at: :desc).flat_map do |d|
      d.attachments.select { |a| image?(a) }.map { |a| [d, a] }
    end
  end

  def image?(att)
    att.content_type.to_s.start_with?("image/") ||
      SeismicTool::EnqueueJob::IMAGE_EXT.include?(File.extname(att.filename.to_s).downcase)
  end

  def disk_path(att)
    f = att.respond_to?(:diskfile) ? att.diskfile : att.file
    p = f.respond_to?(:path) ? f.path : f.to_s
    p.presence && File.exist?(p) ? p : nil
  rescue StandardError
    nil
  end

  def model_params
    d = SeismicModelJob::DEFAULT_PARAMS
    {
      "highlight_cracks" => params[:highlight_cracks] == "1",
      "groove" => params[:groove].to_f.clamp(0.0, 0.3),
      "crack_conf" => (params[:crack_conf].presence || d["crack_conf"]).to_f.clamp(0.05, 0.95),
      "max_points" => (params[:max_points].presence || d["max_points"]).to_i.clamp(20_000, 1_000_000),
      "mesh_side" => (params[:mesh_side].presence || d["mesh_side"]).to_i.clamp(64, 640),
      "max_side" => d["max_side"]
    }.merge(polygon_param)
  end

  # Optional area of interest: JSON [[x, y], ...] in 0..1 coordinates of the upright image.
  def polygon_param
    pts = JSON.parse(params[:polygon].to_s)
    return {} unless pts.is_a?(Array) && pts.size.between?(3, 500)

    pts = pts.map { |x, y| [x.to_f.clamp(0.0, 1.0).round(5), y.to_f.clamp(0.0, 1.0).round(5)] }
    { "polygon" => pts }
  rescue JSON::ParserError, TypeError
    {}
  end

  def model_json(job)
    { id: job.id, status: job.status, error: job.error, duration_ms: job.duration_ms,
      stats: job.stats, active: job.active? }
  end
end
