# frozen_string_literal: true

module Textus
  module Workflows
    Materialize = Textus::Workflow::DSL::Definition.new("materialize").tap do |wf|
      wf.handles "entry.written", "entry.deleted", "entry.moved",
                 "proposal.accepted", "proposal.rejected"
      wf.priority 10
      wf.max_attempts 3
      wf.step :converge do |data, ctx|
        Textus::Produce::Engine.converge(container: ctx.container, call: ctx.call, keys: [ctx.key])
        data
      end
    end
  end
end
