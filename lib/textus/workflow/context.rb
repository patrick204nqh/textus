# frozen_string_literal: true

require_relative "../produce/context_helpers"

module Textus
  module Workflow
    Context = Data.define(:key, :entry, :config, :lane, :container, :call) do
      include Textus::Produce::ContextHelpers
    end
  end
end
