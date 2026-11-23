# frozen_string_literal: true

class SeismicAedesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_form, only: %i[show update destroy print prefill]

  menu_item :seismic_tool
  layout 'base'

  def index
    redirect_to project_seismic_jobs_path(@project)
  end

  def create
    type = SeismicTool::Forms::TYPES.key?(params[:form_type].to_s) ? params[:form_type].to_s : "a_dc"
    schema = SeismicTool::Forms.schema(type)
    form = AedesForm.create!(project: @project, author: User.current, form_type: type,
                             title: params[:title].presence || "#{schema.label.split(' (').first} – #{@project.name}",
                             data: SeismicTool::Forms.prefill(type, @project))
    redirect_to project_seismic_aede_path(@project, form)
  end

  def show
    @summary = SeismicTool::DamageSummary.new(@project)
  end

  def print
    render layout: false
  end

  def update
    schema = @form.schema
    allowed = schema.keys
    submitted = params.fetch(:aedes, {}).to_unsafe_h.slice(*allowed)
    # multi fields arrive as arrays; blank hidden markers are removed
    submitted.transform_values! { |v| v.is_a?(Array) ? v.compact_blank : v.to_s.strip }
    @form.title = params[:title] if params[:title].present?
    @form.status = params[:status] if AedesForm::STATUSES.include?(params[:status])
    merged = @form.data.to_h.merge(submitted)
    merged.merge!(schema.computed(merged))
    @form.data = merged.compact_blank
    @form.save!
    flash[:notice] = "AeDES form saved."
    redirect_to project_seismic_aede_path(@project, @form)
  end

  # Re-applies the project data to the empty fields; fields the user filled in are kept.
  def prefill
    if params[:source] == "wp" && @form.form_type == "a_dc"
      refresh_damage_from_work_packages
      return redirect_to project_seismic_aede_path(@project, @form)
    end

    fresh = SeismicTool::Forms.prefill(@form.form_type, @project)
    overwrite = params[:overwrite] == "1"
    @form.data = overwrite ? @form.data.to_h.merge(fresh) : fresh.merge(@form.data.to_h)
    @form.save!
    redirect_to project_seismic_aede_path(@project, @form)
  end

  def destroy
    @form.destroy
    redirect_to project_seismic_jobs_path(@project)
  end

  private

  # Replaces the damage sections (A16/A17/A20/A21) with what the AeDES work packages say now.
  def refresh_damage_from_work_packages
    kept = @form.data.to_h.reject { |k, _| SeismicTool::AdcFromWorkPackages::OWNED_KEY.match?(k) }
    @form.data = kept.merge(SeismicTool::AdcFromWorkPackages.new(@project).call)
    @form.save!
    flash[:notice] = "Damage sections updated from the AeDES work packages."
  end

  def find_form
    @form = AedesForm.where(project: @project).find(params[:id])
  end
end
