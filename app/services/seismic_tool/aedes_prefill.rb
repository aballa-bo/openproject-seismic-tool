# frozen_string_literal: true

module SeismicTool
  # Builds the initial data of an AeDES form from what the project already
  # knows: project name/description, the "Building data (AeDES)" project custom
  # fields (see the AddBuildingProjectCustomFields migration), the 3D viewer's
  # location, and the damage found by the image analysis.
  class AedesPrefill
    # form key -> project custom field name
    PROJECT_FIELDS = {
      "s1_provincia" => "Provincia",
      "s1_comune" => "Comune",
      "s1_frazione" => "Frazione / Località",
      "s1_istat_provincia" => "Codice ISTAT provincia",
      "s1_istat_comune" => "Codice ISTAT comune",
      "s1_via" => "Indirizzo (via, corso...)",
      "s1_civico" => "Numero civico",
      "s1_lat" => "Latitudine (°)",
      "s1_lon" => "Longitudine (°)",
      "s1_catasto" => "Dati catastali (particelle)",
      "s1_denominazione" => "Denominazione edificio / proprietario",
      "s2a_piani" => "N° piani totali (con interrati)",
      "s2a_altezza" => "Altezza media di piano (m)",
      "s2a_superficie" => "Superficie media di piano (m²)",
      "s2a_unita" => "Numero unità d'uso",
      "s2a_occupanti" => "Occupanti ordinari"
    }.freeze

    # form key -> [project custom field name, { list value => form code }]
    LIST_FIELDS = {
      "s1_posizione" => ["Posizione edificio", { "Isolato" => "1", "Interno" => "2", "D'estremità" => "3", "D'angolo" => "4" }],
      "s1_classe_uso" => ["Classe d'uso", { "Classe I" => "1", "Classe II" => "2", "Classe III" => "3", "Classe IV" => "4" }],
      "s2a_proprieta" => ["Proprietà", { "Pubblica" => "A", "Privata" => "B" }]
    }.freeze

    USE_CODES = { "Residenziale" => "A", "Produttivo" => "B", "Commercio" => "C", "Uffici" => "D",
                  "Servizi pubblici" => "E", "Deposito" => "F", "Strategico" => "G",
                  "Turistico-ricettivo" => "H", "Parcheggio" => "I", "Attività sportive" => "J",
                  "Spazi espositivi" => "K" }.freeze

    def initialize(project)
      @project = project
    end

    def call
      data = {}
      data["s1_denominazione"] = @project.name
      data["s1_data"] = Date.current.iso8601

      values = custom_values_by_name
      PROJECT_FIELDS.each do |key, name|
        v = values[name]
        data[key] = v.to_s if v.present?
      end
      LIST_FIELDS.each do |key, (name, map)|
        v = values[name]
        data[key] = map[v.to_s] if map[v.to_s]
      end
      if (code = USE_CODES[values["Uso prevalente"].to_s])
        data["s2a_uso"] = [code]
      end

      apply_viewer_location(data)
      note = DamageSummary.new(@project).to_text
      data["s9_analisi"] = note if note.present?
      data.compact_blank
    end

    private

    def custom_values_by_name
      return {} unless @project.respond_to?(:custom_field_values)

      @project.custom_field_values.each_with_object({}) do |cfv, h|
        h[cfv.custom_field.name] = cfv.typed_value.respond_to?(:value) ? cfv.typed_value.value : cfv.typed_value
      end
    rescue StandardError => e
      Rails.logger.warn("[seismic_tool] custom field prefill failed: #{e.message}")
      {}
    end

    # Falls back on the 3D viewer's location when the project has no coordinates.
    def apply_viewer_location(data)
      return if data["s1_lat"].present? && data["s1_lon"].present?
      return unless defined?(::SpatialModel) && ::SpatialModel.column_names.include?("latitude")

      m = ::SpatialModel.where(project: @project).where.not(latitude: nil, longitude: nil).order(:id).first
      return unless m

      data["s1_lat"] = m.latitude.to_s
      data["s1_lon"] = m.longitude.to_s
      data["s1_coord_tipo"] = "geo"
      data["s1_datum"] = "WGS84"
    end
  end
end
