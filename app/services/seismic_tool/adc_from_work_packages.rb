# frozen_string_literal: true

module SeismicTool
  # Compiles the damage parts of the Modello A-DC from the AeDES work packages
  # of a project: A16 (level and kind per collapse mechanism), A20 (suggested
  # emergency measures) and A21 (damage to the decorative apparatus / non
  # structural elements). A17 (damage index) is derived from A16.
  class AdcFromWorkPackages
    KIND = { "Sismico" => "sismico", "Pregresso" => "pregresso", "Aggravamento" => "aggravamento" }.freeze
    RANK = { "Aggravamento" => 3, "Sismico" => 2, "Pregresso" => 1 }.freeze
    OWNED_KEY = /\A(a16_\d+_(livello|tipo)|a20_\d+_(lim|est)|a21_danno|a21_desc|a17_(n|d|id))\z/

    def initialize(project)
      @project = project
    end

    def call
      damages = AedesWorkPackages.damages(@project)
      data = {}
      structural(damages.select { |d| d.kind == :structural && d.mechanism && d.level }, data)
      measures(damages, data)
      non_structural(damages.select { |d| d.kind == :non_structural }, data)
      data.merge(AdcSchema.computed(data)).compact_blank
    rescue StandardError => e
      Rails.logger.warn("[seismic_tool] AeDES work package compile failed: #{e.class}: #{e.message}")
      {}
    end

    private

    # Worst level per mechanism; at equal level the more significant kind wins.
    def structural(list, data)
      list.group_by(&:mechanism).each do |m, items|
        next unless (1..AdcSchema::MECHANISMS.size).cover?(m)

        best = items.max_by { |d| [d.level, RANK.fetch(d.damage_type.to_s, 0)] }
        data["a16_#{m}_livello"] = best.level.to_s
        data["a16_#{m}_tipo"] = KIND[best.damage_type.to_s].to_s
      end
    end

    def measures(damages, data)
      damages.each do |d|
        key = d.extent.to_s.start_with?("Estesi") ? "est" : "lim"
        d.pi.each do |p|
          n = p.to_s[/\A\d+/]
          data["a20_#{n}_#{key}"] = "1" if n
        end
      end
    end

    def non_structural(list, data)
      return if list.empty?

      lines = list.map do |d|
        what = d.element.presence || d.degradation.presence || "elemento"
        lvl = d.level ? " – livello #{d.level}" : ""
        "- #{what}#{lvl}#{d.damage_type.present? ? " (#{d.damage_type.downcase})" : ''}: " \
          "#{d.work_package.subject} [WP ##{d.work_package.id}]"
      end
      data["a21_danno"] = lines.join("\n")
      elements = list.filter_map { |d| d.element.presence }.uniq
      data["a21_desc"] = elements.join(", ") if elements.any?
    end
  end
end
