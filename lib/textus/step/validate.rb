# frozen_string_literal: true

module Textus
  module Step
    # Checks an artifact/store state and returns diagnostics. Replaces the
    # :validate RPC. Receives only `caps:` (injected by the registry).
    class Validate < Base
      def self.required_kwargs = []
    end
  end
end
