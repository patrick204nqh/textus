# frozen_string_literal: true

require "fileutils"
require "date"
require "digest"

module Textus
  module Action
    class Ingest < Base
      verb :ingest
      summary "Capture external source material into the raw lane. Write-once, agent-owned."
      surfaces :cli, :mcp
      arg :kind,  String, required: true, positional: true,
                          description: "source kind: url | file | asset"
      arg :slug,  String, required: true,
                          description: "human slug for the key suffix (kebab-case)"
      arg :url,   String, description: "remote URL (required when kind=url)"
      arg :path,  String, description: "local file path (required when kind=file or kind=asset)"
      arg :zone,  String, description: "asset group subdirectory (required when kind=asset)"
      arg :label, String, description: "human label stored in source.label"
      view { |env| { "key" => env.key, "uid" => env.uid, "etag" => env.etag } }

      SOURCE_KINDS = %w[url file asset].freeze
      CONTENT_HASH_ALGO = "sha256"
      TOMBSTONE_RETAIN = %w[ingested_at].freeze

      def self.call(container:, call:, kind:, slug:, url: nil, path: nil, zone: nil, label: nil, **) # rubocop:disable Metrics/ParameterLists
        validation = validate_inputs(kind:, url:, path:, zone:)
        return validation if validation.is_a?(Dry::Monads::Result::Failure)

        now = Time.now.utc
        key = derive_key(now, kind:, slug:)

        content_hash = compute_content_hash(kind:, url:, path:)
        mentry = container.manifest.resolver.resolve(key).entry
        ts = now.iso8601
        structured = build_structured(ts, container, now, content_hash, kind:, url:, path:, label:, zone:)

        store = container.job_store
        index = Textus::Store::Index::Lookup.new(store: store)
        duplicate_key = find_duplicate(index, content_hash, kind:, url:)

        result = if duplicate_key && duplicate_key != key
                   supersede_entry(duplicate_key, key, structured, container, call, store: store, kind:, zone:)
                 else
                   env = write_raw_entry(key, structured, mentry, container, call)
                   rebuild_index(container, store)
                   env
                 end
        Success(result)
      end

      def self.validate_inputs(kind:, url:, path:, zone:)
        unless SOURCE_KINDS.include?(kind)
          return Failure(code: :usage_error,
                         message: "ingest kind must be one of #{SOURCE_KINDS.join("|")}, got #{kind.inspect}")
        end
        case kind
        when "url"
          return Failure(code: :usage_error, message: "ingest url requires --url") unless url
        when "file"
          return Failure(code: :usage_error, message: "ingest file requires --path") unless path
        when "asset"
          return Failure(code: :usage_error, message: "ingest asset requires --path") unless path
          return Failure(code: :usage_error, message: "ingest asset requires --zone") unless zone
        end
        nil
      end

      # Key derivation for Gate pre-dispatch auth. Must match the runtime
      # derivation in #call so the same key is checked by auth and used by
      # the action body.
      def self.dispatch_key(kind:, slug:, **)
        derive_key(Time.now.utc, kind:, slug:)
      end

      def self.derive_key(now, kind:, slug:)
        date = now.strftime("%Y.%m.%d")
        "raw.#{date}.#{kind}-#{slug}"
      end

      def self.compute_content_hash(kind:, url:, path:)
        digest = Digest::SHA256.new
        case kind
        when "url"
          digest.update(url)
        when "file", "asset"
          digest.file(path)
        end
        "#{CONTENT_HASH_ALGO}:#{digest.hexdigest}"
      end

      def self.build_structured(timestamp, container, now, content_hash, kind:, url:, path:, label:, zone:) # rubocop:disable Metrics/ParameterLists
        base = { "ingested_at" => timestamp, "content_hash" => content_hash }
        case kind
        when "url"
          base.merge("source" => { "kind" => "url", "url" => url, "label" => label || url },
                     "body" => nil)
        when "file"
          body_content = File.read(path)
          base.merge("source" => { "kind" => "file", "path" => path,
                                   "label" => label || File.basename(path) },
                     "body" => body_content)
        when "asset"
          asset_rel = copy_asset_file(container, now, path:, zone:)
          base.merge("source" => { "kind" => "asset",
                                   "label" => label || File.basename(path) },
                     "asset" => asset_rel,
                     "body" => nil)
        end
      end

      def self.write_raw_entry(key, structured, mentry, container, call)
        container.compositor.write(key, mentry: mentry,
                                        payload: Textus::Value::Payload.new(
                                          meta: nil, body: nil, content: structured,
                                        ), call: call)
      end

      def self.find_duplicate(index, content_hash, kind:, url:)
        dup = index.find_by_hash(content_hash)
        return dup if dup

        return unless kind == "url"

        index.find_by_url(url)
      end

      def self.rebuild_index(container, store)
        Textus::Store::Index::Builder.new(store: store).rebuild!(resolver: container.manifest.resolver)
      end

      def self.supersede_entry(old_key, new_key, structured, container, call, store:, kind:, zone:) # rubocop:disable Metrics/ParameterLists
        old_mentry = container.manifest.resolver.resolve(old_key).entry

        old_env = container.compositor.read(old_key)
        old_content = old_env&.content || {}
        tombstone = {}
        TOMBSTONE_RETAIN.each do |k|
          tombstone[k] = old_content[k] if old_content.key?(k)
        end
        source_kind = old_content.dig("source", "kind")
        tombstone["source"] = { "kind" => source_kind } if source_kind
        tombstone["superseded_by"] = new_key

        container.compositor.write(old_key, mentry: old_mentry,
                                            payload: Textus::Value::Payload.new(
                                              meta: nil, body: nil, content: tombstone,
                                            ), call: call)

        structured["supersedes"] = old_key
        env = write_raw_entry(new_key, structured, container.manifest.resolver.resolve(new_key).entry, container, call)

        move_asset_file(container, old_content["asset"], zone:) if kind == "asset" && old_content["asset"]

        rebuild_index(container, store)
        env
      end

      def self.move_asset_file(container, old_asset_rel, zone:)
        old_path = File.join(container.root, "assets", old_asset_rel)
        return unless File.exist?(old_path)

        now = Time.now.utc
        date_path = now.strftime("%Y/%m/%d")
        filename = File.basename(old_path)
        new_dir = File.join(container.root, "assets", "raw", date_path, zone)
        new_path = File.join(new_dir, filename)

        return if old_path == new_path

        FileUtils.mkdir_p(new_dir)
        FileUtils.mv(old_path, new_path)
      rescue Errno::ENOENT, Errno::EACCES => e
        warn "[textus ingest] could not move asset #{old_asset_rel}: #{e.message}"
      end

      def self.copy_asset_file(container, now, path:, zone:)
        date_path = now.strftime("%Y/%m/%d")
        filename  = File.basename(path)
        assets_dir = File.join(container.root, "assets", "raw", date_path, zone)
        FileUtils.mkdir_p(assets_dir)
        FileUtils.cp(path, File.join(assets_dir, filename))
        create_gitignore_sentinel(container)
        "raw/#{date_path}/#{zone}/#{filename}"
      end

      def self.create_gitignore_sentinel(container)
        assets_root = File.join(container.root, "assets")
        FileUtils.mkdir_p(assets_root)
        sentinel = File.join(assets_root, ".gitignore")
        File.write(sentinel, "*\n") unless File.exist?(sentinel)
      end
    end
  end
end
