require "fileutils"

module Textus
  module Application
    module Write
      # Materializes a single Derived manifest entry onto disk by running
      # the builder pipeline (template + projection + external runner).
      # Extracted from Application::Write::Build so that Publish can reuse
      # it without creating a Build dependency.
      class Materializer
        def initialize(container:, call:)
          @container  = container
          @call       = call
          @manifest   = container.manifest
          @file_store = container.file_store
          @rpc        = container.rpc
          @root       = container.root
        end

        # Runs the builder pipeline for `mentry` and returns the on-disk
        # target_path string.
        def run(mentry)
          reader = Textus::Application::Read::Get.new(container: @container, call: @call)
          lister = Textus::Application::Read::List.new(container: @container)
          Builder::Pipeline.run(
            mentry: mentry,
            manifest: @manifest,
            reader: reader.method(:call),
            lister: lister.method(:call),
            rpc: @rpc,
            template_loader: ->(name) { read_template(name) },
            transform_context: @container,
            inject_boot: -> { Textus::Boot.run_via(container: @container, role: @call.role) },
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
