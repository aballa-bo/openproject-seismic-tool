# frozen_string_literal: true

module SeismicTool
  # Registry of the supported paper forms. Each entry is a schema module that
  # responds to: label, description, sections, keys, field(key), display(spec, value),
  # summary_key (textarea that receives the image-analysis summary), computed(data).
  module Forms
    TYPES = {
      "a_dc" => "SeismicTool::AdcSchema",
      "gl_aedes" => "SeismicTool::AedesSchema"
    }.freeze

    module_function

    def schema(type) = TYPES.fetch(type.to_s, TYPES["a_dc"]).constantize

    def options = TYPES.keys.map { |k| [schema(k).label, k] }

    def prefill(type, project)
      type.to_s == "gl_aedes" ? AedesPrefill.new(project).call : AdcPrefill.new(project).call
    end
  end
end
