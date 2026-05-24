# frozen_string_literal: true

# Recipe: fetch a folder from a public GitHub repo as a single intake entry.
#
# To use: copy this file into your store's hooks/ directory (e.g.
# .textus/hooks/github_folder.rb), then add a manifest entry referencing
# `intake.handler: github_folder`. See docs/recipe-github-skill-bundle.md.
#
# Pair with skill_fanout.rb to fan the bundle out into per-file derived
# entries.

require "base64"
require "json"
require "net/http"
require "time"
require "uri"

module TextusRecipes
  module GithubFolder
    DEFAULT_FETCHER = lambda do |url|
      res = Net::HTTP.get_response(URI(url))
      raise Textus::UsageError.new("github_folder: GET #{url} returned #{res.code}") unless res.is_a?(Net::HTTPSuccess)

      res.body
    end

    class << self
      attr_accessor :fetcher
    end
    self.fetcher = DEFAULT_FETCHER

    def self.fetch_files(repo, ref, prefix)
      tree_url = "https://api.github.com/repos/#{repo}/git/trees/#{ref}?recursive=1"
      tree = JSON.parse(fetcher.call(tree_url))

      files = {}
      tree.fetch("tree").each do |entry|
        next unless entry["type"] == "blob"
        next unless entry["path"].start_with?(prefix)

        blob = JSON.parse(fetcher.call(entry["url"]))
        unless blob["encoding"] == "base64"
          raise Textus::UsageError.new("github_folder: unexpected blob encoding #{blob["encoding"].inspect}")
        end

        rel = entry["path"].sub(prefix, "")
        files[rel] = Base64.decode64(blob["content"]).force_encoding(Encoding::UTF_8)
      end
      files
    end

    def self.register
      Textus.intake(:github_folder) do |config:, **|
        repo = config["repo"] or raise Textus::UsageError.new("github_folder requires config.repo (owner/repo)")
        ref  = config["ref"]  or raise Textus::UsageError.new("github_folder requires config.ref (branch or sha)")
        path = config["path"] or raise Textus::UsageError.new("github_folder requires config.path (folder prefix in repo)")

        prefix = path.sub(%r{/\z}, "") + "/"
        files = TextusRecipes::GithubFolder.fetch_files(repo, ref, prefix)

        {
          _meta: {
            "source_repo" => repo,
            "source_ref" => ref,
            "source_path" => path,
            "fetched_at" => Time.now.utc.iso8601,
            "file_count" => files.size,
          },
          content: { "files" => files },
        }
      end
    end
  end
end

# Auto-register when this file is loaded by the store's hook loader.
# When required outside a store context (e.g. from a spec), there is no
# active registry on the thread, so .current_registry raises UsageError —
# the caller is then responsible for invoking `.register` inside
# `Textus.with_registry`.
begin
  Textus.current_registry
  TextusRecipes::GithubFolder.register
rescue Textus::UsageError
  # No active registry; defer registration to the caller.
end
