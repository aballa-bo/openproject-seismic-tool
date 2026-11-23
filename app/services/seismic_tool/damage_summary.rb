# frozen_string_literal: true

module SeismicTool
  # Aggregates the finished image analyses of a project (latest result per
  # attachment) into counts per damage class and crack statistics.
  class DamageSummary
    # Italian: used only in the text written into the (Italian) survey form.
    CLASS_LABELS = {
      "Cracks" => "fessure",
      "Fabric loss of masonry units" => "perdita di materiale dei conci",
      "Surface dissolution" => "dissoluzione superficiale",
      "Efflorescence" => "efflorescenze",
      "Discolouration" => "alterazione cromatica",
      "Plant" => "vegetazione",
      "Moss" => "muschio"
    }.freeze

    # English: used everywhere in the web interface.
    CLASS_LABELS_EN = {
      "Cracks" => "cracks",
      "Fabric loss of masonry units" => "fabric loss of masonry units",
      "Surface dissolution" => "surface dissolution",
      "Efflorescence" => "efflorescence",
      "Discolouration" => "discolouration",
      "Plant" => "plants",
      "Moss" => "moss"
    }.freeze

    def self.label(cls) = CLASS_LABELS_EN.fetch(cls, cls)

    def initialize(project)
      @project = project
    end

    def results
      @results ||= begin
        ids = SeismicImageResult.joins(:seismic_job)
                                .where(seismic_jobs: { project_id: @project.id }, status: "done")
                                .where.not(attachment_id: nil)
                                .group(:attachment_id).maximum(:id).values
        SeismicImageResult.where(id: ids).order(:filename).to_a
      end
    end

    def images_analysed = results.size

    def images_with_damage = results.count { |r| r.classes_found.any? }

    def counts
      results.each_with_object(Hash.new(0)) do |r, h|
        r.summary.to_h.each { |k, v| h[k] += v.to_i }
      end
    end

    def crack_stats
      cracks = results.flat_map(&:cracks)
      return nil if cracks.empty?

      widths = cracks.filter_map { |c| c["mean_width_px"] }
      lengths = cracks.filter_map { |c| c["length_px"] }
      {
        count: cracks.size,
        max_length_px: lengths.max,
        max_mean_width_px: widths.max
      }
    end

    def empty? = results.empty?

    def to_text
      return "" if empty?

      lines = ["Analisi automatica di #{images_analysed} immagini (#{images_with_damage} con danni rilevati)."]
      counts.sort_by { |_, v| -v }.each do |cls, n|
        lines << "- #{CLASS_LABELS.fetch(cls, cls)}: #{n} rilevazioni"
      end
      if (cs = crack_stats)
        lines << "Fessure: #{cs[:count]}; lunghezza massima #{cs[:max_length_px]} px, " \
                 "larghezza media massima #{cs[:max_mean_width_px]} px (la scala in mm/px dipende dalla foto)."
      end
      lines << "Risultato automatico indicativo: va verificato dal rilevatore."
      lines.join("\n")
    end
  end
end
