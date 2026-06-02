require "fileutils"

module Textus
  module Write
    # Materializes a single Derived manifest entry onto disk by running
    # the builder pipeline (template + projection + external runner).
    # Extracted from Write::Build so that Publish can reuse
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
        reader = Textus::Read::GetEntry.new(container: @container, call: @call)
        lister = Textus::Read::List.new(container: @container)
        Builder::Pipeline.run(
          mentry: mentry,
          deps: Builder::Pipeline::Deps.new(
            manifest: @manifest,
            reader: reader.method(:call),
            lister: lister.method(:call),
            rpc: @rpc,
            template_loader: ->(name) { read_template(name) },
            transform_context: @container,
            inject_boot: -> { Textus::Boot.build(container: @container) },
          ),
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
