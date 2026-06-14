module Textus
  class Manifest
    class Entry
      class Base < Entry
        attr_reader :raw, :key, :path, :lane, :schema, :owner, :format, :publish_targets

        # rubocop:disable Metrics/ParameterLists, Lint/MissingSuper
        def initialize(raw:, key:, path:, lane:, schema:, owner:, format:, publish_targets: [])
          @raw = raw
          @key = key
          @path = path
          @lane = lane
          @schema = schema
          @owner = owner
          @format = format
          @publish_targets = Array(publish_targets)
        end
        # rubocop:enable Metrics/ParameterLists, Lint/MissingSuper

        def lane_writers(policy)
          verb = policy.verb_for_lane(@lane)
          policy.roles_with_capability(verb)
        rescue UsageError => e
          raise UsageError.new("entry '#{@key}': #{e.message}")
        end

        def in_proposal_lane?(policy) = policy.queue_lane?(@lane)

        def nested?  = false
        def derived? = false
        def intake?  = false
        def leaf?    = false

        # Production traits. Default false on Base (a leaf/intake entry is neither
        # an out-of-band command nor a projection); Produced overrides both from
        # its source. Lets publish modes call these without a `respond_to?` guard.
        def external?   = false
        def projection? = false

        alias zone lane
        alias in_proposal_zone? in_proposal_lane?

        # Whether git should track this entry's file. Default true; an entry
        # marked `tracked: false` in the manifest stays protocol-readable but is
        # listed in the generated `.gitignore` (ADR 0043). Cross-cutting, so it
        # reads from raw here rather than threading through every constructor.
        def tracked? = @raw["tracked"] != false

        # Single source of truth is @publish_targets (ADR 0094). These
        # derive the ADR-0049/0052 views the publish modes consume.
        def publish_to   = @publish_targets.select(&:to_target?).map(&:to)
        def publish_tree = @publish_targets.find(&:tree_target?)&.tree

        # Nil stubs for cross-cutting optional attrs. Subclasses override the
        # ones they own. Validators and serializers can call these directly
        # without `respond_to?` guards.
        def events         = {}
        def ignore         = []

        # Per-entry ignore (ADR 0042). Base entries enumerate no tree, so
        # nothing is ever ignored; Nested overrides with real patterns.
        def ignored?(_rel_path) = false

        # Minimal context object passed into entry `publish_via` hooks.
        # Everything beyond the three primitives is derived. Data.define
        # instances are frozen, so we recompute per-call rather than
        # memoizing — RoleScope/Step::Context construction is cheap.
        PublishContext = ::Data.define(:container, :call, :reader) do
          def manifest   = container.manifest
          def root       = container.root
          def repo_root  = File.dirname(container.root)
          def steps      = container.steps

          def hook_context
            Textus::Step::Context.new(scope: scope_for_hooks)
          end

          def emit(event, **payload)
            steps.publish(event, ctx: hook_context, **payload)
          end

          # Read a named template from the store's templates/ directory.
          # Raises TemplateError when the file doesn't exist.
          def read_template(name)
            path = File.join(container.root.to_s, "templates", name)
            unless File.exist?(path)
              raise Textus::TemplateError.new(
                "template '#{name}' not found",
                template_name: name,
              )
            end
            File.read(path)
          end

          private

          def scope_for_hooks
            Textus::Surfaces::RoleScope.new(
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
        # Write::Build, or nil to skip.
        def publish_via(pctx, prefix: nil)
          publish_mode.publish(pctx, prefix: prefix)
        end
      end
    end
  end
end
