# frozen_string_literal: true

module Textus
  module Action
    class Composite < Base
      def self.chain(*steps)
        @chain = steps
      end

      def self.chain_steps = @chain

      def self.call(container:, call:, **inputs)
        result = nil
        chain_steps.each { |step| result = send(step, container:, call:, **inputs) }
        result
      end
    end
  end
end
