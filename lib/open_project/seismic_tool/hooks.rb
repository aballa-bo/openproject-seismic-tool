# frozen_string_literal: true

require 'open_project/hook'

module OpenProject
  module SeismicTool
    class Hooks < ::OpenProject::Hook::ViewListener
      CSS = '/assets/openproject_seismic_tool/seismic.css'
      JS = '/assets/openproject_seismic_tool/seismic.js'

      def view_layouts_base_html_head(context = {})
        controller = context[:controller]
        return '' unless controller

        vc = controller.view_context
        if controller.is_a?(::SeismicJobsController) || controller.is_a?(::SeismicAedesController)
          return "#{vc.stylesheet_link_tag(CSS)}\n" \
                 "#{vc.nonced_javascript_include_tag(JS, skip_pipeline: true)}".html_safe
        end

        # "Analyse images" shortcut on the document page.
        if defined?(::DocumentsController) && controller.is_a?(::DocumentsController) &&
           controller.action_name == 'show' && controller.instance_variable_get(:@document) &&
           User.current.allowed_in_project?(:run_seismic_analysis, controller.instance_variable_get(:@document).project)
          doc = controller.instance_variable_get(:@document)
          url = vc.new_project_seismic_job_path(doc.project, document_ids: [doc.id])
          return "#{vc.nonced_javascript_include_tag(JS, skip_pipeline: true)}" \
                 "<meta name=\"seismic-doc-link\" content=\"#{ERB::Util.html_escape(url)}\">".html_safe
        end
        ''
      end
    end
  end
end
