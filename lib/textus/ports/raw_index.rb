# frozen_string_literal: true

require "yaml"
require "fileutils"

module Textus
  module Ports
    class RawIndex
      def initialize(root:)
        @root = root
        @path = Layout.raw_index(root)
      end

      def path
        @path
      end

      def load
        return empty_index unless File.exist?(@path)

        YAML.safe_load_file(@path) || empty_index
      rescue StandardError
        empty_index
      end

      def save(index)
        FileUtils.mkdir_p(File.dirname(@path))
        File.write(@path, YAML.dump(index))
        index
      end

      def find_by_hash(content_hash)
        index = load
        index["hashes"]&.fetch(content_hash, nil)
      end

      def find_by_url(url)
        return nil unless url

        index = load
        index["urls"]&.fetch(url, nil)
      end

      def upsert(content_hash:, url:, key:)
        index = load
        index["hashes"] ||= {}
        index["urls"] ||= {}
        index["hashes"][content_hash] = key
        index["urls"][url] = key if url
        save(index)
      end

      private

      def empty_index
        { "hashes" => {}, "urls" => {} }
      end
    end
  end
end
