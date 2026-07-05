# frozen_string_literal: true

module Textus
  module Workflow
    class Registry
      class UnknownWorkflow < KeyError
      end

      def self.load_all(root)
        geometry = Textus::Protocol::Layout.new(root)
        return [] unless File.directory?(geometry.workflow_dir)

        Workflow::DSL::Definition.clear_registered
        Dir.glob(File.join(geometry.workflow_dir, "**", "*.rb")).each { |path| load path }
        Workflow::DSL::Definition.definitions
      end

      attr_reader :definitions

      def initialize(workflow_definitions)
        @definitions = workflow_definitions
        @by_event = {}
        @by_type  = {}

        workflow_definitions.each do |wf|
          @by_type[wf.type] = wf
          wf.handled_events.each { |ev| (@by_event[ev] ||= []) << wf }
        end
      end

      def workflows_for(event_type)
        @by_event.fetch(event_type.to_s, [])
      end

      def for(workflow_type)
        @by_type[workflow_type.to_s] or raise(UnknownWorkflow.new("Unknown workflow type: #{workflow_type}"))
      end

      def match_for_key(key)
        @definitions.find { |wf| wf.match?(key) }
      end

      def workflows_for_key(key)
        @definitions.select { |wf| wf.match?(key) }
                    .sort_by(&:priority)
      end
    end
  end
end
