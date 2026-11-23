# frozen_string_literal: true

module SeismicTool
  # Pre-fills the Modello A-DC from the project data (see the
  # AddBuildingProjectCustomFields migration for the custom fields).
  class AdcPrefill < AedesPrefill
    TEXT_FIELDS = {
      "a3_regione" => "Regione", "a3_provincia" => "Provincia", "a3_istat" => "Codice ISTAT comune",
      "a3_comune" => "Comune", "a3_localita" => "Frazione / Località", "a3_indirizzo" => "Indirizzo (via, corso...)",
      "a3_civico" => "Numero civico", "a3_foglio" => "Foglio catastale", "a3_particelle" => "Dati catastali (particelle)",
      "a3_sub" => "Subalterno catastale",
      "a5_denominazione" => "Denominazione edificio / proprietario", "a5_storica" => "Denominazione storica",
      "a5_anno" => "Datazione (anno / secolo / epoca)", "a5_utilizzatore" => "Utilizzatore",
      "a24_aula_larghezza" => "Larghezza aula (m)", "a24_aula_lunghezza" => "Lunghezza aula (m)",
      "a24_aula_altezza" => "Altezza media aula (m)", "a24_facciata_larghezza" => "Larghezza facciata (m)",
      "a24_facciata_altezza" => "Altezza facciata (m)", "a24_campanile_altezza" => "Altezza campanile (m)"
    }.freeze

    TIPOLOGIA = { "Chiesa" => "chiesa", "Canonica" => "canonica", "Palazzo" => "palazzo", "Castello" => "castello",
                  "Torre" => "torre", "Bene archeologico" => "archeologico", "Altro" => "altro" }.freeze

    def call
      values = custom_values_by_name
      data = { "a1_data" => Date.current.iso8601, "a5_denominazione" => @project.name }
      TEXT_FIELDS.each do |key, name|
        v = values[name]
        data[key] = v.to_s if v.present?
      end
      if (code = TIPOLOGIA[values["Tipologia del bene"].to_s])
        data["a2_tipologia"] = [code]
      end
      data["a5_proprieta_tipo"] = values["Proprietà"].to_s if values["Proprietà"].present?

      u = User.current
      if u&.logged?
        data["a13_cognome"] = u.lastname.to_s
        data["a13_nome"] = u.firstname.to_s
        data["a13_email"] = u.mail.to_s
      end

      location(data, values)
      note = DamageSummary.new(@project).to_text
      data["a23_note"] = note if note.present?
      data.merge!(AdcFromWorkPackages.new(@project).call)
      data.compact_blank
    end

    private

    # Decimal degrees from the project fields or the 3D viewer's location.
    def location(data, values)
      lat = values["Latitudine (°)"]
      lon = values["Longitudine (°)"]
      if (lat.blank? || lon.blank?) && defined?(::SpatialModel) && ::SpatialModel.column_names.include?("latitude")
        m = ::SpatialModel.where(project: @project).where.not(latitude: nil, longitude: nil).order(:id).first
        lat, lon = m&.latitude, m&.longitude
      end
      return if lat.blank? || lon.blank?

      data["a4_nord"] = lat.to_s
      data["a4_est"] = lon.to_s
      data["a4_quadrante"] = "WGS84 (gradi decimali)"
    end
  end
end
