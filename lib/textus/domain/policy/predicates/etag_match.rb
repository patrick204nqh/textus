# frozen_string_literal: true

module Textus
  module Domain
    module Policy
      module Predicates
        # Advisory pre-flight etag check for policy explain. The
        # authoritative compare-and-write stays in Envelope::IO::Writer
        # (atomic write-then-audit, ADR 0017). Passes when no if_etag is
        # supplied (params[:if_etag] nil) — guard does not require it.
        class EtagMatch
          attr_reader :reason

          def initialize(if_etag: nil)
            @if_etag = if_etag
          end

          def name = "etag_match"

          def call(eval)
            return true if @if_etag.nil?
            return true if eval.envelope.nil? # creating; Writer handles race
            return true if eval.envelope.etag == @if_etag

            @reason = "etag mismatch: wanted #{@if_etag}, have #{eval.envelope.etag}"
            false
          end
        end
      end
    end
  end
end
