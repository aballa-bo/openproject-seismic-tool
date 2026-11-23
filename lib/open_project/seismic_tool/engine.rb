# frozen_string_literal: true

require 'open_project/plugins'

module OpenProject
  module SeismicTool
    class Engine < ::Rails::Engine
      engine_name :openproject_seismic_tool

      include OpenProject::Plugins::ActsAsOpEngine

      register 'openproject-seismic_tool',
               author_url: 'https://github.com/aballa-bo/openproject-seismic-tool',
               bundled: true do

        project_module :seismic_tool do
          permission :view_seismic_tool,
                     { seismic_jobs: %i[index show status image],
                       seismic_aedes: %i[index show print],
                       seismic_suggestions: %i[index confirm reject reopen] },
                     permissible_on: :project,
                     public: false

          permission :run_seismic_analysis,
                     { seismic_jobs: %i[new create cancel retry destroy] },
                     permissible_on: :project,
                     require: :member

          permission :edit_aedes_forms,
                     { seismic_aedes: %i[create update destroy prefill] },
                     permissible_on: :project,
                     require: :member
        end

        menu :project_menu,
             :seismic_tool,
             { controller: '/seismic_jobs', action: 'index' },
             caption: ->(_project) { I18n.t('seismic_tool.label_seismic', default: 'Seismic tool') },
             icon: 'pulse',
             after: :documents
      end

      initializer 'seismic_tool.register_assets' do |app|
        app.config.assets.paths << root.join('app/assets/stylesheets')
        app.config.assets.paths << root.join('app/assets/javascripts')
      end

      config.to_prepare do
        require 'open_project/seismic_tool/hooks'
      end
    end
  end
end
