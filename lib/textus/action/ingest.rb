# frozen_string_literal: true

require "fileutils"
require "date"
require "digest"

module Textus
  module Action
    class Ingest < Base
      extend Textus::Contract::DSL

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

      def initialize(kind:, slug:, url: nil, path: nil, zone: nil, label: nil)
        super()
        @kind  = kind
        @slug  = slug
        @url   = url
        @path  = path
        @zone  = zone
        @label = label
      end

      def call(container:, call:)
        validate_inputs!

        now = Time.now.utc
        key = derive_key(now)

        Textus::Gate::Auth.new(container).check_action!(
          action: :ingest, actor: call.role, key: key,
        )

        content_hash = compute_content_hash
        writer = Textus::Envelope::Writer.from(container: container, call: call)
        mentry = container.manifest.resolver.resolve(key).entry
        ts = now.iso8601
        structured = build_structured(ts, container, now, content_hash)

        Textus::Port::Store.open(container.root) do |store|
          index = Textus::Index::Lookup.new(store: store)
          duplicate_key = find_duplicate(index, content_hash)

          if duplicate_key && duplicate_key != key
            supersede_entry(duplicate_key, key, structured, container, call, store: store)
          else
            env = write_raw_entry(key, structured, mentry, writer)
            rebuild_index(container, store)
            env
          end
        end
      end

      private

      def validate_inputs!
        unless SOURCE_KINDS.include?(@kind)
          raise Textus::UsageError.new(
            "ingest kind must be one of #{SOURCE_KINDS.join("|")}, got #{@kind.inspect}",
          )
        end
        case @kind
        when "url"
          raise Textus::UsageError.new("ingest url requires --url") unless @url
        when "file"
          raise Textus::UsageError.new("ingest file requires --path") unless @path
        when "asset"
          raise Textus::UsageError.new("ingest asset requires --path") unless @path
          raise Textus::UsageError.new("ingest asset requires --zone") unless @zone
        end
      end

      def derive_key(now)
        date = now.strftime("%Y.%m.%d")
        "raw.#{date}.#{@kind}-#{@slug}"
      end

      def compute_content_hash
        digest = Digest::SHA256.new
        case @kind
        when "url"
          digest.update(@url)
        when "file", "asset"
          digest.file(@path)
        end
        "#{CONTENT_HASH_ALGO}:#{digest.hexdigest}"
      end

      def build_structured(timestamp, container, now, content_hash)
        base = { "ingested_at" => timestamp, "content_hash" => content_hash }
        case @kind
        when "url"
          base.merge("source" => { "kind" => "url", "url" => @url, "label" => @label || @url },
                     "body" => nil)
        when "file"
          body_content = File.read(@path)
          base.merge("source" => { "kind" => "file", "path" => @path,
                                   "label" => @label || File.basename(@path) },
                     "body" => body_content)
        when "asset"
          asset_rel = copy_asset_file(container, now)
          base.merge("source" => { "kind" => "asset",
                                   "label" => @label || File.basename(@path) },
                     "asset" => asset_rel,
                     "body" => nil)
        end
      end

      def write_raw_entry(key, structured, mentry, writer)
        writer.put(key, mentry: mentry,
                        payload: Textus::Envelope::Writer::Payload.new(
                          meta: nil, body: nil, content: structured,
                        ))
      end

      def find_duplicate(index, content_hash)
        dup = index.find_by_hash(content_hash)
        return dup if dup

        return unless @kind == "url"

        index.find_by_url(@url)
      end

      def rebuild_index(container, store)
        Textus::Index::Builder.new(store: store).rebuild!(resolver: container.manifest.resolver)
      end

      def supersede_entry(old_key, new_key, structured, container, call, store:)
        old_mentry = container.manifest.resolver.resolve(old_key).entry
        writer = Textus::Envelope::Writer.from(container: container, call: call)

        reader = Textus::Envelope::Reader.from(container: container)
        old_env = reader.read(old_key)
        old_content = old_env&.content || {}
        tombstone = {}
        TOMBSTONE_RETAIN.each do |k|
          tombstone[k] = old_content[k] if old_content.key?(k)
        end
        source_kind = old_content.dig("source", "kind")
        tombstone["source"] = { "kind" => source_kind } if source_kind
        tombstone["superseded_by"] = new_key

        writer.put(old_key, mentry: old_mentry,
                            payload: Textus::Envelope::Writer::Payload.new(
                              meta: nil, body: nil, content: tombstone,
                            ))

        structured["supersedes"] = old_key
        env = write_raw_entry(new_key, structured, container.manifest.resolver.resolve(new_key).entry, writer)

        move_asset_file(container, old_content["asset"]) if @kind == "asset" && old_content["asset"]

        rebuild_index(container, store)
        env
      end

      def move_asset_file(container, old_asset_rel)
        old_path = File.join(container.root, "assets", old_asset_rel)
        return unless File.exist?(old_path)

        now = Time.now.utc
        date_path = now.strftime("%Y/%m/%d")
        filename = File.basename(old_path)
        new_dir = File.join(container.root, "assets", "raw", date_path, @zone)
        new_path = File.join(new_dir, filename)

        return if old_path == new_path

        FileUtils.mkdir_p(new_dir)
        FileUtils.mv(old_path, new_path)
      rescue Errno::ENOENT, Errno::EACCES => e
        warn "[textus ingest] could not move asset #{old_asset_rel}: #{e.message}"
      end

      def copy_asset_file(container, now)
        date_path = now.strftime("%Y/%m/%d")
        filename  = File.basename(@path)
        assets_dir = File.join(container.root, "assets", "raw", date_path, @zone)
        FileUtils.mkdir_p(assets_dir)
        FileUtils.cp(@path, File.join(assets_dir, filename))
        create_gitignore_sentinel(container)
        "raw/#{date_path}/#{@zone}/#{filename}"
      end

      def create_gitignore_sentinel(container)
        assets_root = File.join(container.root, "assets")
        FileUtils.mkdir_p(assets_root)
        sentinel = File.join(assets_root, ".gitignore")
        File.write(sentinel, "*\n") unless File.exist?(sentinel)
      end
    end
  end
end
