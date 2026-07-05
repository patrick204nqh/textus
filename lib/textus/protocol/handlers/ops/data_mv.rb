require "fileutils"

module Textus
  module Protocol
    module Handlers
      module Ops
        class DataMv
          def call(from:, to:, ctx:, dry_run: false)
            raise Textus::UsageError.new("from and to required") unless from && to
            raise Textus::UsageError.new("data lane '#{from}' not declared") unless ctx.manifest.data.declared_lane_kinds.key?(from)

            dest_dir = ctx.layout.lane_path(to)
            raise Textus::UsageError.new("destination data/#{to} already exists") if File.exist?(dest_dir)

            affected_keys = ctx.manifest.data.entries.select { |e| e.lane == from }.map(&:key)
            steps = [{ "op" => "rename_zone", "from" => from, "to" => to }]
            steps += affected_keys.map { |k| { "op" => "mv", "from" => k, "to" => "#{to}#{k[from.length..]}" } }
            plan = Textus::Protocol::Retention::Plan.new(steps:, warnings: [])
            return plan.to_h if dry_run

            rewrite_manifest!(from:, to:, ctx:)
            FileUtils.mv(ctx.layout.lane_path(from), dest_dir)
            plan.to_h
          end

          private

          def rewrite_manifest!(from:, to:, ctx:)
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
end
