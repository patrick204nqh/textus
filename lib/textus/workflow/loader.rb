module Textus
  module Workflow
    class Loader
      def self.load_all(root)
        geometry = Textus::Store::Geometry.new(root)
        registry = Registry.new
        return registry unless File.directory?(geometry.workflow_dir)

        collector = Collector.new(registry)
        Collector.with(collector) do
          Dir.glob(File.join(geometry.workflow_dir, "**", "*.rb")).each { |path| load path }
        end
        registry
      end
    end
  end
end
