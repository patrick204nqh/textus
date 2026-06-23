require "yaml"

module Textus
  module Handlers
    class DataMv
      def initialize(container:)
        @container = container
      end

      def call(command, _call)
        manifest = @container.manifest
        geom = @container.geometry

        return Value::Result.failure(:usage_error, "from and to required") if command.from.nil? || command.to.nil?
        unless manifest.data.declared_lane_kinds.key?(command.from)
          return Value::Result.failure(:usage_error,
                                "data lane '#{command.from}' not declared")
        end

        dest_dir = geom.lane_path(command.to)
        return Value::Result.failure(:usage_error, "destination 'data/#{command.to}' already exists") if File.exist?(dest_dir)

        affected_keys = manifest.data.entries.select { |entry| entry.lane == command.from }.map(&:key)

        steps = [{ "op" => "rename_zone", "from" => command.from, "to" => command.to }]
        steps += affected_keys.map do |key|
          { "op" => "mv", "from" => key, "to" => "#{command.to}#{key[command.from.length..]}" }
        end

        plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: [])
        return Value::Result.success(plan) if command.dry_run

        rewrite_manifest!(geom, from: command.from, to: command.to)
        FileUtils.mv(geom.lane_path(command.from), dest_dir)
        Value::Result.success(plan)
      end

      private

      def rewrite_manifest!(geom, from:, to:)
        path = geom.manifest_path
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
