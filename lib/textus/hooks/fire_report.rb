# frozen_string_literal: true

module Textus
  module Hooks
    # Outcome of a single Dispatcher#publish call.
    #
    # fired      — hook names that ran to completion
    # errored    — hook names that raised
    # timed_out  — hook names whose worker thread exceeded the deadline
    #
    # Callers that care about hook health (tests, strict embedders) can
    # check #ok? or inspect #failures. The dispatcher itself never raises
    # on a hook failure unless strict: true was passed to #publish.
    class FireReport
      attr_reader :fired, :errored, :timed_out

      def initialize(fired:, errored:, timed_out:)
        @fired = fired.freeze
        @errored = errored.freeze
        @timed_out = timed_out.freeze
        freeze
      end

      def ok?
        @errored.empty? && @timed_out.empty?
      end

      def failures
        @errored + @timed_out
      end
    end
  end
end
