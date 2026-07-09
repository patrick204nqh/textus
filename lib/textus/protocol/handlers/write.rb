module Textus
  module Protocol
    module Handlers
      module Write
        include Concern

        module_function

        def put(key:, ctx:, call:, meta: nil, if_etag: nil, format: nil, data: nil)
          body, content = data.is_a?(Hash) ? [nil, data] : [data, nil]
          env = ctx.put(key:, meta: meta || {}, body:, content:, if_etag:, call:, format:)
          response(ok: true, key:, uid: env.uid, etag: env.etag)
        end

        def delete(key:, ctx:, call:, if_etag: nil)
          ctx.delete(key:, if_etag:, call:)
          response(ok: true, key:, deleted: true)
        end

        def key_delete(key:, ctx:, call:, if_etag: nil)
          delete(key:, ctx:, call:, if_etag:)
        end

        def move(old_key:, new_key:, ctx:, call:, if_etag: nil, dry_run: false)
          mctx = ctx.move(from_key: old_key, to_key: new_key, call:, if_etag:, dry_run:)
          base = response(ok: true, from_key: mctx.from_key, to_key: mctx.to_key,
                          from_path: mctx.from_path, to_path: mctx.to_path)
          return base.merge("dry_run" => true) if mctx.dry_run

          base.merge("uid" => mctx.envelope.uid, "envelope" => mctx.envelope.to_h_for_wire)
        end

        def key_mv_under(from_under:, to_under:, ctx:, call:, dry_run: false)
          planner = Ops::BulkPlanner.new
          plan = planner.plan_mv(from_under:, to_under:, ctx:)
          return plan.to_h if dry_run

          plan.steps.each { |s| move(old_key: s["from"], new_key: s["to"], ctx:, call:) }
          plan.to_h
        end

        def key_delete_under(under:, ctx:, call:, dry_run: false)
          planner = Ops::BulkPlanner.new
          plan = planner.plan_delete(prefix:, ctx:)
          return plan.to_h if dry_run

          plan.steps.each { |s| delete(key: s["key"], ctx:, call:) }
          plan.to_h
        end

        def data_mv(from:, to:, ctx:, call:, dry_run: false)
          Ops::DataMv.new.call(from:, to:, ctx:, dry_run:)
        end
      end
    end
  end
end
