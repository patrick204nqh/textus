module Textus
  module Protocol
    module Handlers
      module Read
        include Concern

        module_function

        def get(key:, ctx:, call:)
          env = ctx.read(key:)
          unless env
            suggestions = ctx.manifest.resolver.suggestions_for(key)
            raise Textus::UnknownKey.new(key, suggestions:)
          end

          Ops::SourceExpander.new.call(env, ctx:, depth: 0).to_h_for_wire
        end

        def list(ctx:, call:, under: nil, lane: nil, q: nil, schema: nil)
          response(data: ctx.list(under:, lane:, q:, schema:))
        end

        def where(key:, ctx:, call:)
          res = ctx.resolve(key:)
          response(key:, lane: res.entry.lane, path: res.path)
        end

        def uid(key:, ctx:, call:)
          env = ctx.read(key:)
          raise Textus::UnknownKey.new(key) unless env

          response(uid: env.uid)
        end

        def deps(key:, ctx:, call:)
          entry = ctx.manifest.data.entries.find { |e| e.key == key }
          deps_list = entry&.external? ? Array(entry.source&.sources).compact : []
          response(key:, deps: deps_list.uniq)
        end

        def rdeps(key:, ctx:, call:)
          source_rdeps = ctx.manifest.data.entries.each_with_object([]) do |entry, acc|
            next unless entry.external?

            sources = Array(entry.source&.sources).compact
            acc << entry.key if sources.any? { |s| s == key || key.start_with?("#{s}.") }
          end
          link_rdeps = ctx.link_store.links_to(key)
          response(key:, rdeps: (source_rdeps + link_rdeps).uniq.sort)
        end

        def graph(key:, ctx:, call:, depth: nil)
          from = ctx.link_store.links_from(key)
          to   = ctx.link_store.links_to(key)
          response(key:, neighbors: (from + to).uniq.sort,
                   reachable: ctx.link_store.reachable(from: key, depth:).sort)
        end

        def schema_show(key:, ctx:, call:)
          mentry = ctx.mentry_for(key:)
          schema = ctx.schemas.fetch_or_nil(mentry.schema)
          response(key:, schema_ref: mentry.schema, schema: schema&.to_h)
        end

        def blueprint(sub_verb:, key:, data: nil, ctx:, call:)
          _ = call
          case sub_verb
          when "show"
            Protocol::Blueprint::Controller.show(key, schemas: ctx.schemas, manifest: ctx.manifest)
          when "validate"
            payload = Textus::Value::Payload.new(meta: {}, body: data.to_s, content: nil)
            errors = Protocol::Blueprint::Controller.validate(key, payload,
                                                              schemas: ctx.schemas, manifest: ctx.manifest)
            errors.empty? ? { valid: true } : { valid: false, errors: errors }
          when "scaffold"
            Protocol::Blueprint::Controller.scaffold(key, schemas: ctx.schemas, manifest: ctx.manifest)
          else
            raise Textus::UsageError.new("unknown blueprint sub-action: #{sub_verb.inspect} (use: show, validate, scaffold)")
          end
        end
      end
    end
  end
end
