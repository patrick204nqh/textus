module Textus
  module Workflow
    class Loader
      def self.load_all(root)
        registry      = Registry.new
        workflows_dir = File.join(root, "workflows")
        return registry unless File.directory?(workflows_dir)

        collector = Collector.new(registry)
        Collector.with(collector) do
          Dir.glob(File.join(workflows_dir, "**", "*.rb")).sort.each { |path| load path }
        end
        registry
      end
    end
  end
end
