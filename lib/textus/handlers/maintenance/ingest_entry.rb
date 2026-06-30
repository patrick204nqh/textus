require "fileutils"
require "date"
require "digest"

module Textus
  module Handlers
    module Maintenance
      module IngestEntry
        HANDLES = Dispatch::Contracts::IngestEntry
        NEEDS   = %i[manifest file_store schemas audit_log job_store layout].freeze

        SOURCE_KINDS = %w[url file asset].freeze
        CONTENT_HASH_ALGO = "sha256"

        def self.call(command, call, deps)
          unless SOURCE_KINDS.include?(command.kind)
            return Value::Result.failure(:usage_error,
                                         "ingest kind must be one of #{SOURCE_KINDS.join("|")}")
          end

          case command.kind
          when "url"   then return Value::Result.failure(:usage_error, "ingest url requires url") unless command.url
          when "file"  then return Value::Result.failure(:usage_error, "ingest file requires path") unless command.path
          when "asset"
            return Value::Result.failure(:usage_error, "ingest asset requires path") unless command.path
            return Value::Result.failure(:usage_error, "ingest asset requires lane") unless command.lane
          end

          now = Time.now.utc
          key = derive_key(now, command.kind, command.slug)
          content_hash = compute_content_hash(command)
          mentry = deps.manifest.resolver.resolve(key).entry
          ts = now.iso8601

          structured = build_structured(ts, now, content_hash, command, deps)
          store = deps.job_store
          index = Textus::Store::Index::Lookup.new(store:)

          duplicate_key = find_duplicate(index, content_hash, command)

          env = if duplicate_key && duplicate_key != key
                  supersede_entry(duplicate_key, key, structured, call, deps)
                else
                  write_entry(key, structured, mentry, call, deps)
                end

          rebuild_index(store, deps)
          Value::Result.success(env)
        end

        def self.derive_key(now, kind, slug)
          date = now.strftime("%Y.%m.%d")
          "raw.#{date}.#{kind}-#{slug}"
        end

        def self.compute_content_hash(command)
          digest = Digest::SHA256.new
          case command.kind
          when "url" then digest.update(command.url)
          when "file", "asset" then digest.file(command.path)
          end
          "#{CONTENT_HASH_ALGO}:#{digest.hexdigest}"
        end

        def self.build_structured(timestamp, now, content_hash, command, deps)
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
            asset_rel = copy_asset(now, command.path, command.lane, deps)
            base.merge("source" => { "kind" => "asset",
                                     "label" => command.label || File.basename(command.path) },
                       "asset" => asset_rel, "body" => nil)
          end
        end

        def self.copy_asset(now, path, lane, deps)
          date_path = now.strftime("%Y/%m/%d")
          filename  = File.basename(path)
          assets_dir = deps.layout.asset_raw_dir(date_path, lane)
          FileUtils.mkdir_p(assets_dir)
          FileUtils.cp(path, File.join(assets_dir, filename))
          sentinel = deps.layout.asset_sentinel_path
          File.write(sentinel, "*\n") unless File.exist?(sentinel)
          "raw/#{date_path}/#{lane}/#{filename}"
        end

        def self.write_entry(key, structured, mentry, call, deps)
          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          writer = Store::Entry::Writer.new(
            file_store: deps.file_store, manifest: deps.manifest,
            schemas: deps.schemas, audit_log: deps.audit_log,
            call: call, reader: reader, layout: deps.layout
          )
          writer.put(key, mentry: mentry,
                          payload: Textus::Value::Payload.new(meta: nil, body: nil, content: structured))
        end

        def self.find_duplicate(index, content_hash, command)
          dup = index.find_by_hash(content_hash)
          return dup if dup
          return unless command.kind == "url"

          index.find_by_url(command.url)
        end

        def self.supersede_entry(old_key, new_key, structured, call, deps)
          old_mentry = deps.manifest.resolver.resolve(old_key).entry
          reader = Store::Entry::Reader.new(file_store: deps.file_store, manifest: deps.manifest, layout: deps.layout)
          old_env = reader.read(old_key)
          old_content = old_env&.content || {}
          tombstone = {}
          %w[ingested_at].each { |k| tombstone[k] = old_content[k] if old_content.key?(k) }
          source_kind = old_content.dig("source", "kind")
          tombstone["source"] = { "kind" => source_kind } if source_kind
          tombstone["superseded_by"] = new_key

          writer = Store::Entry::Writer.new(
            file_store: deps.file_store, manifest: deps.manifest,
            schemas: deps.schemas, audit_log: deps.audit_log,
            call: call, reader: reader, layout: deps.layout
          )
          writer.put(old_key, mentry: old_mentry,
                              payload: Textus::Value::Payload.new(meta: nil, body: nil, content: tombstone))

          structured["supersedes"] = old_key
          env = write_entry(new_key, structured,
                            deps.manifest.resolver.resolve(new_key).entry, call, deps)

          move_asset(old_content["asset"], command.lane, deps) if command.kind == "asset" && old_content["asset"]

          rebuild_index(deps.job_store, deps)
          env
        end

        def self.move_asset(old_rel, lane, deps)
          old_path = deps.layout.asset_resolve(old_rel)
          return unless File.exist?(old_path)

          now = Time.now.utc
          date_path = now.strftime("%Y/%m/%d")
          filename = File.basename(old_path)
          new_dir = deps.layout.asset_raw_dir(date_path, lane)
          new_path = File.join(new_dir, filename)
          return if old_path == new_path

          FileUtils.mkdir_p(new_dir)
          FileUtils.mv(old_path, new_path)
        rescue Errno::ENOENT, Errno::EACCES => e
          warn "[textus ingest] could not move asset #{old_rel}: #{e.message}"
        end

        def self.rebuild_index(store, deps)
          Textus::Store::Index::Builder.new(store:).rebuild!(resolver: deps.manifest.resolver)
        end
      end
    end
  end
end
