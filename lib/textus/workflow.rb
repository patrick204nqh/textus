module Textus
  module Workflow
    class StepFailed < Textus::Error
      attr_reader :step_name, :cause

      def initialize(step_name, cause)
        @step_name = step_name
        @cause     = cause
        super(:workflow_step_failed, "workflow step '#{step_name}' failed: #{cause.message}")
      end
    end

    class NotFound < Textus::Error
      def initialize(key)
        super(:workflow_not_found, "no workflow matches key '#{key}'; add a .textus/workflows/*.rb file with match: '#{key}'")
      end
    end
  end

  def self.workflow(name, &)
    collector = Workflow::Collector.current
    raise "Textus.workflow called outside Workflow::Loader.load_all context" unless collector

    defn = Workflow::DSL::Definition.new(name)
    defn.instance_eval(&)
    collector.register(defn)
  end
end
