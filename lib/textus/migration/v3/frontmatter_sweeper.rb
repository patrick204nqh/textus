require "json"
require "yaml"

module Textus
  module Migration
    module V3
      module FrontmatterSweeper
        ACTOR_RENAMES = ManifestRewriter::ACTOR_RENAMES

        def self.run(root:)
          Dir.glob(File.join(root, ".textus/zones/**/*")).each do |path|
            next unless File.file?(path)

            case File.extname(path)
            when ".md", ".text", ".txt" then sweep_markdown(path)
            when ".json"                then sweep_json(path)
            when ".yaml", ".yml"        then sweep_yaml(path)
            end
          end
        end

        def self.sweep_markdown(path)
          content = File.read(path)
          new_content = content.sub(/^owner:\s*(\S+)\s*$/) do
            "owner: #{ManifestRewriter.rewrite_owner(::Regexp.last_match(1))}"
          end
          File.write(path, new_content) if new_content != content
        end

        def self.sweep_json(path)
          doc = JSON.parse(File.read(path))
          return unless doc.is_a?(Hash) && doc["_meta"].is_a?(Hash) && doc["_meta"]["owner"]

          new_owner = ManifestRewriter.rewrite_owner(doc["_meta"]["owner"])
          return if new_owner == doc["_meta"]["owner"]

          doc["_meta"]["owner"] = new_owner
          File.write(path, JSON.pretty_generate(doc))
        rescue JSON::ParserError
          # leave malformed files alone
        end

        def self.sweep_yaml(path)
          doc = YAML.safe_load_file(path, aliases: false)
          return unless doc.is_a?(Hash) && doc["_meta"].is_a?(Hash) && doc["_meta"]["owner"]

          new_owner = ManifestRewriter.rewrite_owner(doc["_meta"]["owner"])
          return if new_owner == doc["_meta"]["owner"]

          doc["_meta"]["owner"] = new_owner
          File.write(path, YAML.dump(doc))
        rescue Psych::SyntaxError
          # leave malformed files alone
        end
      end
    end
  end
end
