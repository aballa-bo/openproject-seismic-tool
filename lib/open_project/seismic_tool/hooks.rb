# frozen_string_literal: true

require 'open_project/hook'
require 'digest/md5'

module OpenProject
  module SeismicTool
    class Hooks < ::OpenProject::Hook::ViewListener
      # Served as plain static files with a one-year cache lifetime: append a content hash so a
      # redeploy is picked up without a hard refresh.
      CSS = '/assets/openproject_seismic_tool/seismic.css'
      JS = '/assets/openproject_seismic_tool/seismic.js'
      VIEWER_JS = '/assets/openproject_seismic_tool/viewer3d.js'
      SOURCE_FILES = {
        VIEWER_JS => 'app/assets/javascripts/openproject_seismic_tool/viewer3d.js',
        CSS => 'app/assets/stylesheets/openproject_seismic_tool/seismic.css',
        JS => 'app/assets/javascripts/openproject_seismic_tool/seismic.js'
      }.freeze

      def view_layouts_base_html_head(context = {})
        controller = context[:controller]
        return '' unless controller

        vc = controller.view_context
        if controller.is_a?(::SeismicModelsController)
          return "#{vc.stylesheet_link_tag(bust(CSS))}\n" \
                 "#{vc.nonced_javascript_include_tag(bust(VIEWER_JS), skip_pipeline: true)}".html_safe
        end

        if controller.is_a?(::SeismicJobsController) || controller.is_a?(::SeismicAedesController)
          return "#{vc.stylesheet_link_tag(bust(CSS))}\n" \
                 "#{vc.nonced_javascript_include_tag(bust(JS), skip_pipeline: true)}".html_safe
        end

        # "Analyse images" shortcut on the document page.
        if defined?(::DocumentsController) && controller.is_a?(::DocumentsController) &&
           controller.action_name == 'show' && controller.instance_variable_get(:@document) &&
           User.current.allowed_in_project?(:run_seismic_analysis, controller.instance_variable_get(:@document).project)
          doc = controller.instance_variable_get(:@document)
          url = vc.new_project_seismic_job_path(doc.project, document_ids: [doc.id])
          return "#{vc.nonced_javascript_include_tag(bust(JS), skip_pipeline: true)}" \
                 "<meta name=\"seismic-doc-link\" content=\"#{ERB::Util.html_escape(url)}\">".html_safe
        end
        ''
      end

      private

      def bust(url)
        token = asset_tokens[url]
        token ? "#{url}?v=#{token}" : url
      end

      def asset_tokens
        @asset_tokens ||= SOURCE_FILES.each_with_object({}) do |(url, rel), acc|
          path = Engine.root.join(rel)
          acc[url] = Digest::MD5.file(path).hexdigest[0, 12] if File.exist?(path)
        rescue StandardError
          next
        end
      end
    end
  end
end
