require "fileutils"
require "date"
require "digest"

module Textus
  module Handlers
    class IngestEntry
      SOURCE_KINDS = %w[url file asset].freeze
      CONTENT_HASH_ALGO = "sha256"

      def initialize(container:)
        @container = container
      end

      def call(command, call)
        unless SOURCE_KINDS.include?(command.kind)
          return Value::Result.failure(:usage_error,
                                "ingest kind must be one of #{SOURCE_KINDS.join("|")}")
        end

        case command.kind
        when "url"   then return Value::Result.failure(:usage_error, "ingest url requires url") unless command.url
        when "file"  then return Value::Result.failure(:usage_error, "ingest file requires path") unless command.path
        when "asset"
          return Value::Result.failure(:usage_error, "ingest asset requires path") unless command.path
          return Value::Result.failure(:usage_error, "ingest asset requires zone") unless command.zone
        end

        now = Time.now.utc
        key = derive_key(now, command.kind, command.slug)
        content_hash = compute_content_hash(command)
        mentry = @container.manifest.resolver.resolve(key).entry
        ts = now.iso8601

        structured = build_structured(ts, now, content_hash, command)
        store = @container.job_store
        index = Textus::Store::Index::Lookup.new(store:)

        duplicate_key = find_duplicate(index, content_hash, command)

        env = if duplicate_key && duplicate_key != key
                supersede_entry(duplicate_key, key, structured, call, store, command)
              else
                write_entry(key, structured, mentry, call)
              end

        rebuild_index(store)
        Value::Result.success(env)
      end

      private

      def derive_key(now, kind, slug)
        date = now.strftime("%Y.%m.%d")
        "raw.#{date}.#{kind}-#{slug}"
      end

      def compute_content_hash(command)
        digest = Digest::SHA256.new
        case command.kind
        when "url" then digest.update(command.url)
        when "file", "asset" then digest.file(command.path)
        end
        "#{CONTENT_HASH_ALGO}:#{digest.hexdigest}"
      end

      def build_structured(timestamp, now, content_hash, command)
        base = { "ingested_at" => timestamp, "content_hash" => content_hash }
        case command.kind
        when "url"
          base.merge("source" => { "kind" => "url", "url" => command.url,
                                   "label" => command.label || command.url }, "body" => nil)
        when "file"
          base.merge("source" => { "kind" => "file", "path" => command.path,
                                   "label" => command.label || File.basename(command.path) },
                     "body" => File.read(command.path))
        when "asset"
          asset_rel = copy_asset(now, command.path, command.zone)
          base.merge("source" => { "kind" => "asset",
                                   "label" => command.label || File.basename(command.path) },
                     "asset" => asset_rel, "body" => nil)
        end
      end

      def copy_asset(now, path, zone)
        date_path = now.strftime("%Y/%m/%d")
        filename  = File.basename(path)
        assets_dir = @container.geometry.asset_raw_dir(date_path, zone)
        FileUtils.mkdir_p(assets_dir)
        FileUtils.cp(path, File.join(assets_dir, filename))
        sentinel = @container.geometry.asset_sentinel_path
        File.write(sentinel, "*\n") unless File.exist?(sentinel)
        "raw/#{date_path}/#{zone}/#{filename}"
      end

      def write_entry(key, structured, mentry, call)
        @container.pipeline.write(key, mentry: mentry,
                                       payload: Textus::Value::Payload.new(meta: nil, body: nil, content: structured),
                                       call: call)
      end

      def find_duplicate(index, content_hash, command)
        dup = index.find_by_hash(content_hash)
        return dup if dup
        return unless command.kind == "url"

        index.find_by_url(command.url)
      end

      def supersede_entry(old_key, new_key, structured, call, store, command)
        old_mentry = @container.manifest.resolver.resolve(old_key).entry
        old_env = @container.pipeline.read(old_key)
        old_content = old_env&.content || {}
        tombstone = {}
        %w[ingested_at].each { |k| tombstone[k] = old_content[k] if old_content.key?(k) }
        source_kind = old_content.dig("source", "kind")
        tombstone["source"] = { "kind" => source_kind } if source_kind
        tombstone["superseded_by"] = new_key

        @container.pipeline.write(old_key, mentry: old_mentry,
                                           payload: Textus::Value::Payload.new(meta: nil, body: nil, content: tombstone),
                                           call: call)

        structured["supersedes"] = old_key
        env = write_entry(new_key, structured,
                          @container.manifest.resolver.resolve(new_key).entry, call)

        move_asset(old_content["asset"], command.zone) if command.kind == "asset" && old_content["asset"]

        rebuild_index(store)
        env
      end

      def move_asset(old_rel, zone)
        old_path = @container.geometry.asset_resolve(old_rel)
        return unless File.exist?(old_path)

        now = Time.now.utc
        date_path = now.strftime("%Y/%m/%d")
        filename = File.basename(old_path)
        new_dir = @container.geometry.asset_raw_dir(date_path, zone)
        new_path = File.join(new_dir, filename)
        return if old_path == new_path

        FileUtils.mkdir_p(new_dir)
        FileUtils.mv(old_path, new_path)
      rescue Errno::ENOENT, Errno::EACCES => e
        warn "[textus ingest] could not move asset #{old_rel}: #{e.message}"
      end

      def rebuild_index(store)
        Textus::Store::Index::Builder.new(store:).rebuild!(resolver: @container.manifest.resolver)
      end
    end
  end
end
