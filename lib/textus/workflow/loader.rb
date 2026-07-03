module Textus
  module Workflow
    class Loader
      def self.load_all(root)
        geometry = Textus::Protocol::Layout.new(root)
        defns = []
        return defns unless File.directory?(geometry.workflow_dir)

        Thread.current[:textus_workflow_registry] = defns
        Dir.glob(File.join(geometry.workflow_dir, "**", "*.rb")).each { |path| load path }
        defns
      ensure
        Thread.current[:textus_workflow_registry] = nil
      end
    end
  end
end
