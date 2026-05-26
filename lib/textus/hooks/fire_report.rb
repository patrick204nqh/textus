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
    FireReport = Data.define(:fired, :errored, :timed_out) do
      def initialize(fired:, errored:, timed_out:)
        super(fired: fired.dup.freeze, errored: errored.dup.freeze, timed_out: timed_out.dup.freeze)
      end

      def ok? = errored.empty? && timed_out.empty?
      def failures = errored + timed_out
    end
  end
end
