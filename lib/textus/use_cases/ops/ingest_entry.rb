# frozen_string_literal: true

require "fileutils"
require "date"
require "digest"

module Textus
  module UseCases
    module Ops
      class IngestEntry < Base
        handles Dispatch::Contracts::IngestEntry
        needs :file_system, :manifest, :schemas, :audit_log, :layout, :event_store, :writer, :reader

        SOURCE_KINDS = %w[url file asset].freeze
        CONTENT_HASH_ALGO = "sha256"

        def call
          unless SOURCE_KINDS.include?(command.kind)
            return failure(:usage_error,
                           "ingest kind must be one of #{SOURCE_KINDS.join("|")}")
          end

          case command.kind
          when "url"   then return failure(:usage_error, "ingest url requires url") unless command.url
          when "file"  then return failure(:usage_error, "ingest file requires path") unless command.path
          when "asset"
            return failure(:usage_error, "ingest asset requires path") unless command.path
            return failure(:usage_error, "ingest asset requires lane") unless command.lane
          end

          now = Time.now.utc
          key = derive_key(now, command.kind, command.slug)
          content_hash = compute_content_hash(command)
          mentry = manifest.resolver.resolve(key).entry
          ts = now.iso8601

          structured = build_structured(ts, now, content_hash, command)
          store = event_store
          index = Textus::Store::Index::Lookup.new(store:)

          duplicate_key = find_duplicate(index, content_hash, command)

          env = if duplicate_key && duplicate_key != key
                  supersede_entry(duplicate_key, key, structured)
                else
                  write_entry(key, structured, mentry)
                end

          rebuild_index(store)
          success(env)
        end

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
            asset_rel = copy_asset(now, command.path, command.lane)
            base.merge("source" => { "kind" => "asset",
                                     "label" => command.label || File.basename(command.path) },
                       "asset" => asset_rel, "body" => nil)
          end
        end

        def copy_asset(now, path, lane)
          date_path = now.strftime("%Y/%m/%d")
          filename  = File.basename(path)
          assets_dir = layout.asset_raw_dir(date_path, lane)
          FileUtils.mkdir_p(assets_dir)
          FileUtils.cp(path, File.join(assets_dir, filename))
          sentinel = layout.asset_sentinel_path
          File.write(sentinel, "*\n") unless File.exist?(sentinel)
          "raw/#{date_path}/#{lane}/#{filename}"
        end

        def write_entry(key, structured, mentry)
          writer.put(key, mentry: mentry, call: @call,
                          payload: Textus::Value::Payload.new(meta: nil, body: nil, content: structured))
        end

        def find_duplicate(index, content_hash, command)
          dup = index.find_by_hash(content_hash)
          return dup if dup
          return unless command.kind == "url"

          index.find_by_url(command.url)
        end

        def supersede_entry(old_key, new_key, structured)
          old_mentry = manifest.resolver.resolve(old_key).entry
          old_env = reader.read(old_key)
          old_content = old_env&.content || {}
          tombstone = {}
          %w[ingested_at].each { |k| tombstone[k] = old_content[k] if old_content.key?(k) }
          source_kind = old_content.dig("source", "kind")
          tombstone["source"] = { "kind" => source_kind } if source_kind
          tombstone["superseded_by"] = new_key

          writer.put(old_key, mentry: old_mentry, call: @call,
                              payload: Textus::Value::Payload.new(meta: nil, body: nil, content: tombstone))

          structured["supersedes"] = old_key
          env = write_entry(new_key, structured,
                            manifest.resolver.resolve(new_key).entry)

          lane = command.lane
          move_asset(old_content["asset"], lane) if command.kind == "asset" && old_content["asset"]

          rebuild_index(event_store)
          env
        end

        def move_asset(old_rel, lane)
          old_path = layout.asset_resolve(old_rel)
          return unless File.exist?(old_path)

          now = Time.now.utc
          date_path = now.strftime("%Y/%m/%d")
          filename = File.basename(old_path)
          new_dir = layout.asset_raw_dir(date_path, lane)
          new_path = File.join(new_dir, filename)
          return if old_path == new_path

          FileUtils.mkdir_p(new_dir)
          FileUtils.mv(old_path, new_path)
        rescue Errno::ENOENT, Errno::EACCES => e
          warn "[textus ingest] could not move asset #{old_rel}: #{e.message}"
        end

        def rebuild_index(store)
          Textus::Store::Index::Builder.new(store:).rebuild!(resolver: manifest.resolver)
        end
      end
    end
  end
end
