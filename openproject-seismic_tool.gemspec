# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = "openproject-seismic_tool"
  s.version     = "0.1.0"
  s.authors     = ["Andrea Ballabeni"]
  s.summary     = "Masonry damage detection from images and GL-AeDES post-earthquake form for OpenProject"
  s.description = "Detects cracks and other damage in the images attached to a project's documents, using a " \
                  "low-priority background queue and worker, and builds the AeDES post-earthquake form from " \
                  "the project's data."
  s.license     = "GPL-3.0"

  s.files = Dir["{app,config,db,lib}/**/*", "README.md"]
end
