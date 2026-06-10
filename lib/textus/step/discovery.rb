# frozen_string_literal: true

module Textus
  module Step
    # Maps a discovered file path under .textus/steps to its (kind, name).
    # kind = the directory segment directly under steps/; name = the basename
    # without .rb (hyphens preserved). The single source of truth for valid
    # kinds is the set of Base subclasses.
    KINDS = %i[fetch transform validate observe].freeze

    Discovery = Data.define(:kind, :name) do
      def self.parse(path, base:)
        rel = path.delete_prefix(base.to_s).delete_prefix("/")
        parts = rel.split("/")
        raise UsageError.new("step #{rel} must live under steps/<kind>/<name>.rb") unless parts.length == 2

        kind = parts[0].to_sym
        raise UsageError.new("unknown step kind '#{parts[0]}' (expected one of: #{KINDS.join(", ")})") unless KINDS.include?(kind)

        new(kind: kind, name: File.basename(parts[1], ".rb").to_sym)
      end
    end
  end
end
