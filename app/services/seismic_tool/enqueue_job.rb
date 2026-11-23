# frozen_string_literal: true

module SeismicTool
  # Creates a SeismicJob with one queued SeismicImageResult per image attached
  # to the given documents. The Python worker picks them up one image at a time.
  class EnqueueJob
    IMAGE_EXT = %w[.jpg .jpeg .png .bmp .tif .tiff .webp .heic .heif].freeze

    Result = Struct.new(:job, :skipped, :error, keyword_init: true)

    def initialize(project:, user:, documents:, params: {})
      @project = project
      @user = user
      @documents = Array(documents)
      @params = SeismicJob::DEFAULT_PARAMS.merge(params.to_h.stringify_keys)
    end

    def call
      attachments = @documents.flat_map { |d| d.attachments.to_a }.select { |a| image?(a) }
      return Result.new(error: :no_images) if attachments.empty?

      job = nil
      skipped = 0
      SeismicJob.transaction do
        job = SeismicJob.create!(project: @project, user: @user, document: @documents.first,
                                 params: @params, total_images: attachments.size)
        job.update!(output_dir: SeismicJob.storage_root.join("jobs", job.id.to_s).to_s)
        attachments.each do |att|
          path = disk_path(att)
          if path.blank?
            skipped += 1
            job.seismic_image_results.create!(attachment: att, filename: att.filename, status: "failed",
                                              error: "File not on local disk (remote storage is not supported)")
            next
          end
          job.seismic_image_results.create!(attachment: att, filename: att.filename, source_path: path,
                                            digest: att.digest)
        end
        job.update!(failed_images: skipped)
        job.update!(status: "failed", finished_at: Time.current) if skipped == attachments.size
      end
      Result.new(job: job, skipped: skipped)
    end

    private

    def image?(att)
      att.content_type.to_s.start_with?("image/") || IMAGE_EXT.include?(File.extname(att.filename.to_s).downcase)
    end

    def disk_path(att)
      f = att.respond_to?(:diskfile) ? att.diskfile : att.file
      p = f.respond_to?(:path) ? f.path : f.to_s
      p.presence && File.exist?(p) ? p : nil
    rescue StandardError
      nil
    end
  end
end
