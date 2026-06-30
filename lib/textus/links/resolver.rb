# frozen_string_literal: true

require "pathname"

module Textus
  module Links
    class Resolver
      class UnknownKeyError < StandardError
      end

      def initialize(manifest:)
        @manifest = manifest
      end

      # Resolve a textus:KEY reference to a Markdown-ready link target.
      #
      # Returns a relative path string if the target entry has a publish.to,
      # or a "`textus get KEY`" string if not.
      # Raises UnknownKeyError if the key is not declared in the manifest.
      def resolve(key:, from_path:)
        entry = @manifest.data.entries.find { |e| e.key == key }
        raise UnknownKeyError.new("unknown key: #{key}") unless entry

        to = Array(entry.publish_to).first
        return "`textus get #{key}`" if to.nil?

        relative_path(from: from_path, to: to)
      end

      private

      def relative_path(from:, to:)
        from_dir = Pathname.new(from).dirname
        Pathname.new(to).relative_path_from(from_dir).to_s
      end
    end
  end
end
