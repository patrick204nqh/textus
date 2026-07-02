# frozen_string_literal: true

module Textus
  module Workflow
    class Registry
      UnknownWorkflow = Class.new(KeyError)

      def initialize(workflow_definitions)
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
        @by_type[workflow_type.to_s] or raise UnknownWorkflow, "Unknown workflow type: #{workflow_type}"
      end
    end
  end
end
