# frozen_string_literal: true

module Textus
  module Step
    # Acquires data from outside the store (the `fetch:` build input). Returns
    # either { "content" => Hash } (structured) or { _meta:, body: } (rendered
    # text). Replaces the :resolve_handler RPC. `caps:` is injected by the
    # registry only if #call declares it.
    class Fetch < Base
      def self.kind = :fetch
      def self.required_kwargs = %i[config args]
    end
  end
end
