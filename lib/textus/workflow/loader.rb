module Textus
  module Workflow
    class Loader
      def self.load_all(root)
        geometry = Textus::Protocol::Layout.new(root)
        return [] unless File.directory?(geometry.workflow_dir)

        Workflow::DSL::Definition.clear_registered
        Dir.glob(File.join(geometry.workflow_dir, "**", "*.rb")).each { |path| load path }
        Workflow::DSL::Definition.definitions
      end
    end
  end
end
