# frozen_string_literal: true

# The image analysis only *suggests* damage. A verifier (anyone who can add work
# packages in the project) confirms a suggestion -- choosing mechanism, level,
# kind and measures -- and that creates an AeDES work package; or rejects it.
class SeismicSuggestionsController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :require_verifier, only: %i[confirm reject reopen]
  before_action :find_suggestion, only: %i[confirm reject reopen]

  menu_item :seismic_tool
  layout 'base'

  def index
    SeismicTool::SuggestionBuilder.new(@project).call
    @status = params[:status].to_s.presence_in(SeismicSuggestion::STATUSES) || "pending"
    @kind = params[:kind].to_s.presence_in(%w[structural non_structural])
    @min = params[:min].present? ? params[:min].to_f.clamp(0, 1) : 0.3
    scope = SeismicSuggestion.where(project: @project, status: @status).where("confidence >= ?", @min)
    scope = scope.where(kind: @kind) if @kind
    @suggestions = scope.includes(seismic_image_result: :seismic_job, work_package: []).order(confidence: :desc).limit(150)
    @counts = SeismicSuggestion.where(project: @project).group(:status).count
    @types_ready = SeismicTool::AedesWorkPackages.ready?
    @can_verify = verifier?
  end

  def confirm
    unless SeismicTool::AedesWorkPackages.ready?
      return back_with(:error, "The AeDES work package types/custom fields are missing: run the plugin migrations.")
    end

    kind = @suggestion.kind
    level = params[:level].to_s
    return back_with(:error, "Choose the damage level.") unless level.match?(/\A[0-5]\z/)

    mechanism = params[:mechanism].to_s
    if kind == "structural" && !SeismicTool::AedesWorkPackages::MECHANISMS.include?(mechanism)
      return back_with(:error, "Choose the collapse mechanism.")
    end

    result = @suggestion.seismic_image_result
    degradation = SeismicTool::AedesWorkPackages::DEGRADATION.fetch(@suggestion.damage_class, @suggestion.damage_class)
    pi = Array(params[:pi]).select { |x| SeismicTool::AedesWorkPackages::PI.include?(x) }
    values = {
      "AeDES Meccanismo di collasso" => (mechanism if kind == "structural"),
      "AeDES Elemento interessato" => (params[:element].to_s.strip if kind == "non_structural"),
      "AeDES Tipo di degrado" => degradation,
      "AeDES Livello di danno" => SeismicTool::AedesWorkPackages::LEVELS[level.to_i],
      "AeDES Tipo di danno" => params[:damage_type].to_s.presence_in(SeismicTool::AedesWorkPackages::DAMAGE_TYPES),
      "AeDES Provvedimenti di pronto intervento" => pi,
      "AeDES Estensione provvedimenti" => params[:extent].to_s.presence_in(SeismicTool::AedesWorkPackages::EXTENT),
      "AeDES Origine" => "Analisi immagini"
    }.compact_blank

    subject = if kind == "structural"
                "#{mechanism.sub(' – ', ' ')} – #{result.filename}"
              else
                "#{degradation} – #{params[:element].presence || result.filename}"
              end
    wp, error = SeismicTool::AedesWorkPackages.create(
      project: @project, user: User.current, kind: kind, subject: subject,
      description: description_for(result), values: values
    )
    return back_with(:error, "Work package not created: #{error}") unless wp

    @suggestion.update!(status: "confirmed", work_package: wp, decided_by: User.current, decided_at: Time.current)
    flash[:notice] = "Confirmed: work package ##{wp.id} created."
    redirect_to project_seismic_suggestions_path(@project, kind: params[:filter_kind].presence, min: params[:filter_min].presence)
  end

  def reject
    @suggestion.update!(status: "rejected", decided_by: User.current, decided_at: Time.current)
    redirect_to project_seismic_suggestions_path(@project, kind: params[:filter_kind].presence, min: params[:filter_min].presence)
  end

  def reopen
    @suggestion.update!(status: "pending", decided_by: nil, decided_at: nil) unless @suggestion.status == "confirmed"
    redirect_to project_seismic_suggestions_path(@project, status: "pending")
  end

  private

  def verifier? = User.current.allowed_in_project?(:add_work_packages, @project)

  def require_verifier
    deny_access unless verifier?
  end

  def find_suggestion
    @suggestion = SeismicSuggestion.where(project: @project).find(params[:id])
  end

  def back_with(type, message)
    flash[type] = message
    redirect_to project_seismic_suggestions_path(@project)
  end

  def description_for(result)
    job = result.seismic_job
    d = @suggestion.detail.to_h
    lines = ["Suggerimento dall'analisi automatica delle immagini, confermato dal verificante.", "",
             "* Immagine: #{result.filename}",
             "* Classe rilevata: #{@suggestion.damage_class} (confidenza #{@suggestion.confidence&.round(2)})"]
    if d["length_px"]
      lines << "* Fessura: lunghezza #{d['length_px']} px, larghezza media #{d['mean_width_px']} px, area #{d['area_px']} px²"
    end
    lines << "* Riquadro (px): #{d['box']&.map(&:round)&.join(', ')}" if d["box"]
    overlay = result.overlay_path.present? ? "overlay" : "source"
    url = result_image_project_seismic_job_path(@project, job, result_id: result.id, kind: overlay)
    lines << "* [Immagine con evidenza del danno](#{url})"
    note = params[:note].to_s.strip
    lines += ["", "Note del verificante:", note] if note.present?
    lines.join("\n")
  end
end
