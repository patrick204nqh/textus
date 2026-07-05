module Textus
  module Protocol
    module Handlers
      module Write
        include Concern
        extend self

        def put(key:, store:, ctx:, call:, meta: nil, body: nil, content: nil, if_etag: nil)
          env = store.put(key:, meta: meta || {}, body:, content:, if_etag:, call:)
          { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "uid" => env.uid, "etag" => env.etag }
        end

        def delete(key:, store:, ctx:, call:, if_etag: nil)
          store.delete(key:, if_etag:, call:)
          { "protocol" => Textus::PROTOCOL, "ok" => true, "key" => key, "deleted" => true }
        end
        alias key_delete delete

        def move(old_key:, new_key:, store:, ctx:, call:, if_etag: nil, dry_run: false)
          mctx = store.move(from_key: old_key, to_key: new_key, call:, if_etag:, dry_run:)
          base = { "protocol" => Textus::PROTOCOL, "ok" => true,
                   "from_key" => mctx.from_key, "to_key" => mctx.to_key,
                   "from_path" => mctx.from_path, "to_path" => mctx.to_path }
          return base.merge("dry_run" => true) if mctx.dry_run

          base.merge("uid" => mctx.envelope.uid, "envelope" => mctx.envelope.to_h_for_wire)
        end

        def key_mv_prefix(from_prefix:, to_prefix:, store:, ctx:, call:, dry_run: false)
          raise Textus::UsageError.new("from_prefix and to_prefix required") unless from_prefix && to_prefix

          leaves = store.list(prefix: from_prefix)
          raise Textus::UsageError.new("from_prefix is a leaf — use mv") if leaves.any? { |r| r["key"] == from_prefix }

          warnings = leaves.empty? ? ["no keys under #{from_prefix}"] : []
          steps = leaves.map do |row|
            tail = row["key"].delete_prefix("#{from_prefix}.")
            { "op" => "mv", "from" => row["key"], "to" => "#{to_prefix}.#{tail}" }
          end
          plan = Textus::Protocol::Retention::Plan.new(steps:, warnings:)
          return plan.to_h if dry_run

          steps.each { |s| move(old_key: s["from"], new_key: s["to"], store:, ctx:, call:) }
          plan.to_h
        end

        def key_delete_prefix(prefix:, store:, ctx:, call:, dry_run: false)
          raise Textus::UsageError.new("prefix required") unless prefix && !prefix.empty?

          leaves = store.list(prefix:)

          warnings = leaves.empty? ? ["no keys under #{prefix}"] : []
          steps = leaves.map { |row| { "op" => "delete", "key" => row["key"] } }
          plan = Textus::Protocol::Retention::Plan.new(steps:, warnings:)
          return plan.to_h if dry_run

          steps.each { |s| delete(key: s["key"], store:, ctx:, call:) }
          plan.to_h
        end

        def data_mv(from:, to:, store:, ctx:, call:, dry_run: false)
          raise Textus::UsageError.new("from and to required") unless from && to
          raise Textus::UsageError.new("data lane '#{from}' not declared") unless ctx.manifest.data.declared_lane_kinds.key?(from)

          dest_dir = ctx.layout.lane_path(to)
          raise Textus::UsageError.new("destination data/#{to} already exists") if File.exist?(dest_dir)

          affected_keys = ctx.manifest.data.entries.select { |e| e.lane == from }.map(&:key)
          steps = [{ "op" => "rename_zone", "from" => from, "to" => to }]
          steps += affected_keys.map { |k| { "op" => "mv", "from" => k, "to" => "#{to}#{k[from.length..]}" } }
          plan = Textus::Protocol::Retention::Plan.new(steps:, warnings: [])
          return plan.to_h if dry_run

          rewrite_data_mv_manifest!(from:, to:, ctx:)
          FileUtils.mv(ctx.layout.lane_path(from), dest_dir)
          plan.to_h
        end

        private

        def rewrite_data_mv_manifest!(from:, to:, ctx:)
          path = ctx.layout.manifest_path
          raw = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: false)
          raw["lanes"].each { |lane| lane["name"] = to if lane["name"] == from }
          raw["entries"].each do |entry|
            entry["lane"] = to if entry["lane"] == from
            entry["key"] = entry["key"].sub(/\A#{Regexp.escape(from)}(\.|\z)/, "#{to}\\1")
            entry["path"] = entry["path"].sub(%r{\A(data/)?#{Regexp.escape(from)}(/|\z)}, "\\1#{to}\\2")
          end
          File.write(path, YAML.dump(raw))
        end
      end
    end
  end
end
