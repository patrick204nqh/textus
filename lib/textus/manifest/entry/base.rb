module Textus
  class Manifest
    class Entry
      class Base < Entry
        attr_reader :raw, :key, :path, :zone, :schema, :owner, :format, :publish_to

        # rubocop:disable Metrics/ParameterLists, Lint/MissingSuper
        def initialize(raw:, key:, path:, zone:, schema:, owner:, format:, publish_to: [])
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

        def zone_writers(policy)
          policy.zone_writers(@zone)
        rescue UsageError => e
          raise UsageError.new("entry '#{@key}': #{e.message}")
        end

        def in_generator_zone?(policy) = policy.derived_zone?(@zone)
        def in_proposal_zone?(policy)  = policy.queue_zone?(@zone)

        def nested?  = false
        def derived? = false
        def intake?  = false
        def leaf?    = false

        # Whether git should track this entry's file. Default true; an entry
        # marked `tracked: false` in the manifest stays protocol-readable but is
        # listed in the generated `.gitignore` (ADR 0043). Cross-cutting, so it
        # reads from raw here rather than threading through every constructor.
        def tracked? = @raw["tracked"] != false

        # Nil stubs for cross-cutting optional attrs. Subclasses override the
        # ones they own. Validators and serializers can call these directly
        # without `respond_to?` guards.
        def template       = nil
        def inject_boot    = false # rubocop:disable Naming/PredicateMethod
        def events         = {}
        def publish_tree   = nil
        def ignore         = []

        # Per-entry ignore (ADR 0042). Base entries enumerate no tree, so
        # nothing is ever ignored; Nested overrides with real patterns.
        def ignored?(_rel_path) = false

        # Minimal context object passed into entry `publish_via` hooks.
        # Everything beyond the three primitives is derived. Data.define
        # instances are frozen, so we recompute per-call rather than
        # memoizing — RoleScope/Hooks::Context construction is cheap.
        PublishContext = ::Data.define(:container, :call, :reader) do
          def manifest   = container.manifest
          def root       = container.root
          def repo_root  = File.dirname(container.root)
          def events     = container.events

          def hook_context
            Textus::Hooks::Context.new(scope: scope_for_hooks)
          end

          def emit(event, **payload)
            events.publish(event, ctx: hook_context, **payload)
          end

          private

          def scope_for_hooks
            Textus::RoleScope.new(
              container: container, role: call.role, dry_run: call.dry_run,
            )
          end
        end

        # ADR 0049: an entry resolves, once, to one Publish::* mode that owns its
        # publish algorithm. A plain entry publishes via ToPaths (publish_to) or
        # None; Nested resolves among the key/path-driven modes. Derived
        # overrides publish_via to materialize first.
        def publish_mode
          @publish_mode ||= Publish.resolve(self)
        end

        # Returns: { kind: :built|:leaves, value: ... } to be accumulated by
        # Write::Publish, or nil to skip.
        def publish_via(pctx, prefix: nil)
          publish_mode.publish(pctx, prefix: prefix)
        end
      end
    end
  end
end
