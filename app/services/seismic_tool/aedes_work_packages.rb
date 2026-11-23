# frozen_string_literal: true

module SeismicTool
  # The AeDES work package types and their custom fields: creates work packages
  # from confirmed suggestions and reads them back to compile the survey form.
  module AedesWorkPackages
    STRUCTURAL = "AeDES – Danno strutturale"
    NON_STRUCTURAL = "AeDES – Danno non strutturale"

    MECHANISMS = AdcSchema::MECHANISMS.each_with_index.map { |m, i| "#{i + 1} – #{m}" }.freeze
    LEVELS = ["0 – assenza di danno", "1 – danno lieve", "2 – danno moderato", "3 – danno grave",
              "4 – danno molto grave", "5 – crollo"].freeze
    DAMAGE_TYPES = %w[Sismico Pregresso Aggravamento].freeze
    PI = ["1 – Revisione manto di copertura", "2 – Copertura provvisoria", "3 – Puntellamenti",
          "4 – Rimozione delle macerie", "5 – Transennamenti / recinzioni / protezioni",
          "6 – Consolidamenti localizzati", "7 – Messa in opera di cerchiatura e/o tiranti",
          "8 – Ripristino smaltimento delle acque meteoriche", "9 – Monitoraggio",
          "10 – Protezioni o consolidamenti su opere d'arte fisse",
          "11 – Catalogazione e smontaggio delle parti pericolanti", "12 – Sgombero opere d'arte mobili",
          "13 – Raccolta sistematica dei frammenti", "14 – Ricovero e protezione dei frammenti"].freeze
    EXTENT = ["Limitati (*)", "Estesi (**)"].freeze
    DEGRADATION = { "Cracks" => "Fessure", "Fabric loss of masonry units" => "Perdita di materiale dei conci",
                    "Surface dissolution" => "Dissoluzione superficiale", "Efflorescence" => "Efflorescenze",
                    "Discolouration" => "Alterazione cromatica", "Plant" => "Vegetazione", "Moss" => "Muschio" }.freeze
    ORIGIN = ["Analisi immagini", "Rilievo manuale"].freeze

    # name, format, options and the kinds of work package that carry the field
    FIELD_SPECS = [
      { name: "AeDES Meccanismo di collasso", format: "list", options: MECHANISMS, types: %i[structural] },
      { name: "AeDES Elemento interessato", format: "string", types: %i[non_structural] },
      { name: "AeDES Tipo di degrado", format: "list", options: DEGRADATION.values, types: %i[structural non_structural] },
      { name: "AeDES Livello di danno", format: "list", options: LEVELS, types: %i[structural non_structural] },
      { name: "AeDES Tipo di danno", format: "list", options: DAMAGE_TYPES, types: %i[structural non_structural] },
      { name: "AeDES Provvedimenti di pronto intervento", format: "list", options: PI, multi: true,
        types: %i[structural non_structural] },
      { name: "AeDES Estensione provvedimenti", format: "list", options: EXTENT, types: %i[structural non_structural] },
      { name: "AeDES Origine", format: "list", options: ORIGIN, types: %i[structural non_structural] }
    ].freeze

    Damage = Struct.new(:work_package, :kind, :mechanism, :level, :damage_type, :pi, :extent, :degradation,
                        :element, keyword_init: true)

    module_function

    def type_for(kind)
      ::Type.find_by(name: kind.to_s == "structural" ? STRUCTURAL : NON_STRUCTURAL)
    end

    def field(name) = ::WorkPackageCustomField.find_by(name: name)

    def ready?
      type_for(:structural) && type_for(:non_structural) &&
        FIELD_SPECS.all? { |s| field(s[:name]) }
    end

    # Makes sure the type can be used in the project (needed in every OpenProject version).
    def enable_type(project, type)
      enabled = project.respond_to?(:enabled_types) ? project.enabled_types : project.types
      return if enabled.exists?(type.id)

      if project.respond_to?(:types) && project.types.respond_to?(:<<)
        project.types << type
      elsif project.respond_to?(:enabled_types) && project.respond_to?(:type_ids)
        project.update!(type_ids: project.type_ids + [type.id])
      end
    end

    # values: { "AeDES Livello di danno" => "3 – danno grave", "AeDES Provvedimenti ..." => [..] }
    def custom_field_values(values)
      values.each_with_object({}) do |(name, v), h|
        cf = field(name)
        next unless cf && v.present?

        if cf.field_format == "list"
          ids = Array(v).filter_map { |x| cf.custom_options.find_by(value: x)&.id }
          h[cf.id.to_s] = cf.multi_value? ? ids.map(&:to_s) : ids.first.to_s if ids.any?
        else
          h[cf.id.to_s] = v.to_s
        end
      end
    end

    # Creates the work package; returns [work_package, error_message].
    def create(project:, user:, kind:, subject:, description:, values:)
      type = type_for(kind)
      return [nil, "The AeDES work package types do not exist (migration not run?)"] unless type

      enable_type(project, type)
      call = ::WorkPackages::CreateService.new(user: user).call(
        project: project, type: type, subject: subject.to_s.truncate(255), description: description,
        custom_field_values: custom_field_values(values)
      )
      call.success? ? [call.result, nil] : [nil, call.errors.full_messages.join(", ")]
    end

    # All AeDES damage work packages of a project, as Damage structs.
    def damages(project)
      types = { type_for(:structural) => :structural, type_for(:non_structural) => :non_structural }.compact
      return [] if types.empty?

      cfs = FIELD_SPECS.to_h { |s| [s[:name], field(s[:name])] }
      project.work_packages.where(type_id: types.keys.map(&:id)).includes(:custom_values).map do |wp|
        get = lambda do |name|
          cf = cfs[name] or next nil
          raw = wp.custom_values.select { |cv| cv.custom_field_id == cf.id }.map(&:value).compact_blank
          next nil if raw.empty?

          if cf.field_format == "list"
            vals = cf.custom_options.where(id: raw).pluck(:value)
            cf.multi_value? ? vals : vals.first
          else
            raw.first
          end
        end
        mech = get.call("AeDES Meccanismo di collasso").to_s[/\A\d+/]
        Damage.new(work_package: wp, kind: types.find { |t, _| t.id == wp.type_id }&.last,
                   mechanism: mech&.to_i, level: get.call("AeDES Livello di danno").to_s[/\A\d/]&.to_i,
                   damage_type: get.call("AeDES Tipo di danno"), pi: Array(get.call("AeDES Provvedimenti di pronto intervento")),
                   extent: get.call("AeDES Estensione provvedimenti"), degradation: get.call("AeDES Tipo di degrado"),
                   element: get.call("AeDES Elemento interessato"))
      end
    end
  end
end
