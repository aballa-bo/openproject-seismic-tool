# frozen_string_literal: true

class SeismicJobsController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_job, only: %i[show destroy cancel retry image]

  menu_item :seismic_tool
  layout 'base'

  def index
    @jobs = SeismicJob.where(project: @project).includes(:user, :document).recent.limit(100)
    @summary = SeismicTool::DamageSummary.new(@project)
    @worker_alive = SeismicJob.worker_alive?
    @aedes_forms = AedesForm.where(project: @project).order(updated_at: :desc)
  end

  def new
    @documents = @project.documents.includes(:attachments).order(created_at: :desc).select do |d|
      d.attachments.any? { |a| image_attachment?(a) }
    end
    @params = SeismicJob::DEFAULT_PARAMS
  end

  def create
    docs = @project.documents.where(id: Array(params[:document_ids]).map(&:to_i)).to_a
    if docs.empty?
      flash[:error] = "Select at least one document."
      return redirect_to new_project_seismic_job_path(@project)
    end

    result = SeismicTool::EnqueueJob.new(project: @project, user: User.current, documents: docs,
                                         params: job_params).call
    if result.error == :no_images
      flash[:error] = "The selected documents have no image attachments."
      redirect_to new_project_seismic_job_path(@project)
    else
      flash[:notice] = "Analysis queued (#{result.job.total_images} images)."
      redirect_to project_seismic_job_path(@project, result.job)
    end
  end

  def show
    auto_publish if request.format.html?
    @results = @job.seismic_image_results.order(:id)
    respond_to do |format|
      format.html { @worker_alive = SeismicJob.worker_alive? }
      format.json { render json: job_json(@job, @results) }
    end
  end

  # Lightweight polling endpoint for the job list.
  def status
    jobs = SeismicJob.where(project: @project).active.or(SeismicJob.where(project: @project, updated_at: 1.minute.ago..))
    render json: { worker_alive: SeismicJob.worker_alive?,
                   jobs: jobs.map { |j| job_json(j) } }
  end

  def cancel
    @job.cancel! if @job.active?
    redirect_to project_seismic_job_path(@project, @job)
  end

  def retry
    @job.retry!
    redirect_to project_seismic_job_path(@project, @job)
  end

  # Manual (re)publication of the images to the project's Documents.
  def publish
    result = run_publish
    if result.nil?
      flash[:error] = "You are not allowed to add documents in this project."
    elsif result.errors.any?
      flash[:error] = "Published with errors: #{result.errors.first(3).join('; ')}"
    else
      flash[:notice] = "#{result.attached} images added to the Documents (_labeled / _masked)."
    end
    redirect_to project_seismic_job_path(@project, @job)
  end

  def destroy
    @job.destroy
    redirect_to project_seismic_jobs_path(@project)
  end

  # Serves a source image, its crack overlay or its mask.
  def image
    result = @job.seismic_image_results.find(params[:result_id])
    path =
      case params[:kind]
      when "overlay" then result.overlay_path
      when "mask" then result.mask_path
      else result.source_path
      end
    root = SeismicJob.storage_root.to_s
    allowed = result.source_path.to_s == path.to_s || path.to_s.start_with?(root)
    return head(:not_found) unless path.present? && allowed && File.file?(path)

    send_file path, disposition: "inline", type: Marcel::MimeType.for(Pathname.new(path))
  end

  private

  def can_publish? = User.current.allowed_in_project?(:manage_documents, @project)

  def run_publish
    return nil unless can_publish?

    SeismicTool::PublishToDocuments.new(job: @job, user: User.current).call
  end

  # A finished job copies its images to the Documents the first time someone
  # who may add documents opens it.
  def auto_publish
    return if @job.active? || !can_publish?
    return unless @job.seismic_image_results.where(status: "done", published_at: nil).exists?

    result = run_publish
    flash.now[:notice] = "#{result.attached} images added to the Documents (_labeled / _masked)." if result&.attached&.positive?
    flash.now[:error] = "Some images could not be published: #{result.errors.first(2).join('; ')}" if result&.errors&.any?
  rescue StandardError => e
    Rails.logger.warn("[seismic_tool] auto publish failed: #{e.class}: #{e.message}")
  end

  def find_job
    @job = SeismicJob.where(project: @project).find(params[:id])
  end

  def job_params
    p = params.permit(:mode, :conf, :crack_conf, :imgsz, :priority)
    out = {}
    out["mode"] = p[:mode] if %w[cascade detector crack_only].include?(p[:mode])
    out["conf"] = p[:conf].to_f.clamp(0.05, 0.95) if p[:conf].present?
    out["crack_conf"] = p[:crack_conf].to_f.clamp(0.05, 0.95) if p[:crack_conf].present?
    out["imgsz"] = p[:imgsz].to_i.clamp(320, 2560) if p[:imgsz].present?
    out
  end

  def image_attachment?(att)
    att.content_type.to_s.start_with?("image/") ||
      SeismicTool::EnqueueJob::IMAGE_EXT.include?(File.extname(att.filename.to_s).downcase)
  end

  def job_json(job, results = nil)
    h = { id: job.id, status: job.status, total: job.total_images, done: job.done_images,
          failed: job.failed_images, percent: job.progress_percent }
    if results
      h[:results] = results.map do |r|
        { id: r.id, filename: r.filename, status: r.status, summary: r.summary, error: r.error }
      end
    end
    h
  end
end
