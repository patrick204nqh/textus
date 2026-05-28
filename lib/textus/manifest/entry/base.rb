module Textus
  class Manifest
    class Entry
      class Base < Entry
        attr_reader :raw, :key, :path, :zone, :schema, :owner, :format, :manifest, :publish_to

        # rubocop:disable Metrics/ParameterLists, Lint/MissingSuper
        def initialize(manifest:, raw:, key:, path:, zone:, schema:, owner:, format:, publish_to: [])
          @manifest = manifest
          @raw = raw
          @key = key
          @path = path
          @zone = zone
          @schema = schema
          @owner = owner
          @format = format
          @publish_to = Array(publish_to)
        end
        # rubocop:enable Metrics/ParameterLists, Lint/MissingSuper

        def zone_writers
          @manifest.policy.zone_writers(@zone)
        rescue UsageError => e
          raise UsageError.new("entry '#{@key}': #{e.message}")
        end

        def in_generator_zone? = @manifest.policy.zone_kinds(@zone).include?(:generator)
        def in_proposal_zone?  = @manifest.policy.zone_kinds(@zone).include?(:proposer)

        def nested?  = false
        def derived? = false
        def intake?  = false
        def leaf?    = false

        # Nil stubs for cross-cutting optional attrs. Subclasses override the
        # ones they own. Validators and serializers can call these directly
        # without `respond_to?` guards.
        def template       = nil
        def inject_boot    = false # rubocop:disable Naming/PredicateMethod
        def events         = {}
        def publish_each   = nil
        def index_filename = nil

        PublishContext = Struct.new(
          :repo_root, :manifest, :file_store, :root, :caps, :rpc, :boot, :ctx, :bus, :hook_context,
          :reader, :emit, # callables: reader.call(key) → envelope; emit.call(event, **payload)
          keyword_init: true
        )

        # Subclasses override to customize publish behavior.
        # Default: copy the stored file to each publish_to target.
        # Returns: { kind: :built|:leaves, value: ... } to be accumulated by
        # Publish#call, or nil to skip.
        def publish_via(pctx, prefix: nil) # rubocop:disable Lint/UnusedMethodArgument
          return nil if Array(publish_to).empty?

          source_path = pctx.manifest.resolver.resolve(@key).path
          envelope = pctx.reader.call(@key)

          publish_to.each do |rel|
            target_abs = File.join(pctx.repo_root, rel)
            Textus::Infra::Publisher.publish(source: source_path, target: target_abs, store_root: pctx.root)
            pctx.emit.call(:file_published,
                           key: @key,
                           envelope: envelope,
                           source: source_path,
                           target: target_abs)
          end

          { kind: :built, value: { "key" => @key, "path" => source_path, "published_to" => publish_to } }
        end
      end
    end
  end
end
