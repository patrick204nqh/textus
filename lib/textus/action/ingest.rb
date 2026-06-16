# frozen_string_literal: true

require "fileutils"
require "date"

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

        write_raw_entry(key, now, container, call)
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

      def write_raw_entry(key, now, container, call)
        ts     = now.iso8601
        mentry = container.manifest.resolver.resolve(key).entry
        writer = Textus::Envelope::Writer.from(container: container, call: call)

        case @kind
        when "url"
          structured = {
            "ingested_at" => ts,
            "source" => { "kind" => "url", "url" => @url, "label" => @label || @url },
            "body" => nil,
          }
          writer.put(key, mentry: mentry,
                          payload: Textus::Envelope::Writer::Payload.new(
                            meta: nil, body: nil, content: structured,
                          ))
        when "file"
          body_content = File.read(@path)
          structured = {
            "ingested_at" => ts,
            "source" => { "kind" => "file", "path" => @path,
                          "label" => @label || File.basename(@path) },
            "body" => body_content,
          }
          writer.put(key, mentry: mentry,
                          payload: Textus::Envelope::Writer::Payload.new(
                            meta: nil, body: nil, content: structured,
                          ))
        when "asset"
          asset_rel = copy_asset_file(container, now)
          structured = {
            "ingested_at" => ts,
            "source" => { "kind" => "asset",
                          "label" => @label || File.basename(@path) },
            "asset" => asset_rel,
            "body" => nil,
          }
          writer.put(key, mentry: mentry,
                          payload: Textus::Envelope::Writer::Payload.new(
                            meta: nil, body: nil, content: structured,
                          ))
        end
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
