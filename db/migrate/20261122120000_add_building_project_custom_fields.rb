# frozen_string_literal: true

# Project custom fields holding the building data that the AeDES form needs
# and that OpenProject does not have natively (address, ISTAT codes, use
# class, number of storeys...). The AeDES form pre-fills itself from them,
# matching by field *name* -- see SeismicTool::AedesPrefill::PROJECT_FIELDS.
#
# Never aborts the migration: a failure (e.g. a custom field API change in a
# newer OpenProject) is logged and the AeDES form simply starts empty.
class AddBuildingProjectCustomFields < ActiveRecord::Migration[7.0]
  SECTION_NAME = "Building data (AeDES)"

  FIELDS = [
    { name: "Regione",                    format: "string" },
    { name: "Provincia",                  format: "string" },
    { name: "Comune",                     format: "string" },
    { name: "Frazione / Località",        format: "string" },
    { name: "Codice ISTAT provincia",     format: "string" },
    { name: "Codice ISTAT comune",        format: "string" },
    { name: "Indirizzo (via, corso...)",  format: "string" },
    { name: "Numero civico",              format: "string" },
    { name: "Latitudine (°)",             format: "float" },
    { name: "Longitudine (°)",            format: "float" },
    { name: "Dati catastali (particelle)", format: "string" },
    { name: "Posizione edificio",         format: "list",
      options: ["Isolato", "Interno", "D'estremità", "D'angolo"] },
    { name: "Classe d'uso",               format: "list",
      options: ["Classe I", "Classe II", "Classe III", "Classe IV"] },
    { name: "Denominazione edificio / proprietario", format: "string" },
    { name: "N° piani totali (con interrati)", format: "int" },
    { name: "Altezza media di piano (m)", format: "float" },
    { name: "Superficie media di piano (m²)", format: "float" },
    { name: "Anno di costruzione / ristrutturazione", format: "string" },
    { name: "Uso prevalente",             format: "list",
      options: ["Residenziale", "Produttivo", "Commercio", "Uffici", "Servizi pubblici", "Deposito",
                "Strategico", "Turistico-ricettivo", "Parcheggio", "Attività sportive", "Spazi espositivi"] },
    { name: "Numero unità d'uso",         format: "int" },
    { name: "Occupanti ordinari",         format: "int" },
    { name: "Proprietà",                  format: "list", options: ["Pubblica", "Privata"] },
    { name: "Foglio catastale",           format: "string" },
    { name: "Subalterno catastale",       format: "string" },
    { name: "Denominazione storica",      format: "string" },
    { name: "Datazione (anno / secolo / epoca)", format: "string" },
    { name: "Utilizzatore",               format: "string" },
    { name: "Tipologia del bene",         format: "list",
      options: ["Chiesa", "Canonica", "Palazzo", "Castello", "Torre", "Bene archeologico", "Altro"] },
    { name: "Larghezza aula (m)",         format: "float" },
    { name: "Lunghezza aula (m)",         format: "float" },
    { name: "Altezza media aula (m)",     format: "float" },
    { name: "Larghezza facciata (m)",     format: "float" },
    { name: "Altezza facciata (m)",       format: "float" },
    { name: "Altezza campanile (m)",      format: "float" },
    { name: "Materiale struttura verticale", format: "list",
      options: ["C.A. prefabbricato", "C.A. in opera", "Muratura", "Acciaio", "Legno", "Misto acciaio-cls", "Altro"] },
    { name: "Materiale struttura orizzontale", format: "list",
      options: ["C.A. prefabbricato", "C.A. in opera", "Muratura", "Acciaio", "Legno", "Misto acciaio-cls", "Altro"] }
  ].freeze

  def up
    unless defined?(::ProjectCustomField)
      say "ProjectCustomField not available -- skipped"
      return
    end

    section = project_section
    FIELDS.each_with_index do |spec, i|
      next if ::ProjectCustomField.exists?(name: spec[:name])

      cf = ::ProjectCustomField.new(name: spec[:name], field_format: spec[:format])
      cf.project_custom_field_section = section if section && cf.respond_to?(:project_custom_field_section=)
      cf.position = i + 1 if cf.respond_to?(:position=)
      cf.is_required = false if cf.respond_to?(:is_required=)
      cf.admin_only = false if cf.respond_to?(:admin_only=)
      cf.is_filter = false if cf.respond_to?(:is_filter=)
      cf.searchable = false if cf.respond_to?(:searchable=)
      (spec[:options] || []).each_with_index do |v, pos|
        cf.custom_options.build(value: v, position: pos + 1)
      end
      cf.save!
    rescue StandardError => e
      say "could not create project custom field #{spec[:name].inspect}: #{e.class}: #{e.message}"
    end
  rescue StandardError => e
    say "building custom fields skipped: #{e.class}: #{e.message}"
  end

  def down
    return unless defined?(::ProjectCustomField)

    ::ProjectCustomField.where(name: FIELDS.map { |f| f[:name] }).destroy_all
    ::ProjectCustomFieldSection.where(name: SECTION_NAME).destroy_all if defined?(::ProjectCustomFieldSection)
  end

  private

  def project_section
    return unless defined?(::ProjectCustomFieldSection)

    ::ProjectCustomFieldSection.find_or_create_by!(name: SECTION_NAME)
  rescue StandardError => e
    say "no custom field section: #{e.message}"
    nil
  end
end
