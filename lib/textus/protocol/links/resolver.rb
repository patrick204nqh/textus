require "pathname"

module Textus
  module Protocol
    class Links
      class Resolver
        class UnknownKeyError < StandardError
        end

        def initialize(manifest:)
          @manifest = manifest
        end

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
end
