require "fileutils"

module Textus
  module Application
    module Writes
      # Materializes a single Derived manifest entry onto disk by running
      # the builder pipeline (template + projection + external runner).
      # Extracted from Application::Writes::Build so that Publish can reuse
      # it without creating a Build dependency.
      class Materializer
        def initialize(ctx:, ports:, boot:)
          @ctx        = ctx
          @ports      = ports
          @manifest   = ports.manifest
          @file_store = ports.file_store
          @rpc        = ports.rpc_registry
          @root       = ports.root
          @boot       = boot
        end

        # Runs the builder pipeline for `mentry` and returns the on-disk
        # target_path string.
        def run(mentry)
          reader = Textus::Application::Reads::Get.new(ctx: @ctx, ports: @ports)
          lister = Textus::Application::Reads::List.new(ports: @ports)
          Builder::Pipeline.run(
            mentry: mentry,
            manifest: @manifest,
            reader: reader.method(:call),
            lister: lister.method(:call),
            rpc: @rpc,
            template_loader: ->(name) { read_template(name) },
            transform_context: @ports,
            inject_boot: @boot,
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
