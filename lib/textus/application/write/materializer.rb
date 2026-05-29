require "fileutils"

module Textus
  module Application
    module Write
      # Materializes a single Derived manifest entry onto disk by running
      # the builder pipeline (template + projection + external runner).
      # Extracted from Application::Write::Build so that Publish can reuse
      # it without creating a Build dependency.
      class Materializer
        def initialize(ctx:, caps:, rpc:, session:)
          @ctx        = ctx
          @caps       = caps
          @manifest   = caps.manifest
          @file_store = caps.file_store
          @rpc        = rpc
          @root       = caps.root
          @session    = session
        end

        # Runs the builder pipeline for `mentry` and returns the on-disk
        # target_path string.
        def run(mentry)
          reader = Textus::Application::Read::Get.new(container: @caps, call: @ctx)
          lister = Textus::Application::Read::List.new(container: @caps)
          Builder::Pipeline.run(
            mentry: mentry,
            manifest: @manifest,
            reader: reader.method(:call),
            lister: lister.method(:call),
            rpc: @rpc,
            template_loader: ->(name) { read_template(name) },
            transform_context: @caps,
            inject_boot: -> { Textus::Boot.run(@session) },
          )
        end

        private

        def read_template(name)
          tpl_path = File.join(@root, "templates", name)
          raise TemplateError.new("template not found: #{tpl_path}", template_name: name) unless File.exist?(tpl_path)

          File.read(tpl_path)
        end
      end
    end
  end
end
