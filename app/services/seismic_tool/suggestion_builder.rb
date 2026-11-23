# frozen_string_literal: true

module SeismicTool
  # Turns the detections of finished image analyses into pending suggestions
  # (idempotent: one row per result + detection index).
  class SuggestionBuilder
    MAX_PER_IMAGE = 30

    def initialize(project)
      @project = project
    end

    def call
      pending = SeismicImageResult.joins(:seismic_job)
                                  .where(seismic_jobs: { project_id: @project.id }, status: "done")
                                  .where("jsonb_array_length(seismic_image_results.detections) > 0")
                                  .where.not(id: SeismicSuggestion.where(project_id: @project.id)
                                                                  .select(:seismic_image_result_id))
      pending.find_each do |result|
        result.detections.first(MAX_PER_IMAGE).each_with_index do |d, i|
          SeismicSuggestion.create!(
            project: @project, seismic_image_result: result, detection_index: i,
            kind: d["class"] == "Cracks" ? "structural" : "non_structural",
            damage_class: d["class"].to_s, confidence: d["confidence"],
            detail: d.slice("box", "area_px", "length_px", "mean_width_px")
          )
        rescue ActiveRecord::RecordNotUnique
          next
        end
      end
    end
  end
end
