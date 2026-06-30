# frozen_string_literal: true

module Textus
  module Workflow
    Context = Data.define(:key, :entry, :config, :lane, :container, :call) do
      include Textus::ContainerHelpers
    end
  end
end
