# frozen_string_literal: true

require "yaml"

module Textus
  module Action
    class DataMv < Base
      verb :data_mv
      summary "Rename a data lane — manifest + files. Refuses if destination exists."
      surfaces :cli, :mcp
      cli "data mv"
      arg :from, String, required: true, positional: true, description: "current data lane name"
      arg :to, String, required: true, positional: true,
                       description: "new data lane name; refused if a lane by this name already exists"
      arg :dry_run, :boolean, default: false,
                              description: "when true, returns the planned zone move without applying it; " \
                                           "defaults to false, so omitting it applies the move immediately"
      view { |v, _i| v.to_h }

      def self.call(container:, call:, from:, to:, dry_run: false, **) # rubocop:disable Lint/UnusedMethodArgument
        manifest = container.manifest
        geom = container.geometry

        return Failure(code: :usage_error, message: "from and to required") if from.nil? || to.nil? || from.empty? || to.empty?
        return Failure(code: :usage_error, message: "data lane '#{from}' not declared") unless manifest.data.declared_lane_kinds.key?(from)

        dest_dir = geom.lane_path(to)
        return Failure(code: :usage_error, message: "destination 'data/#{to}' already exists") if File.exist?(dest_dir)

        affected_keys = manifest.data.entries.select { |entry| entry.lane == from }.map(&:key)

        steps = [{ "op" => "rename_zone", "from" => from, "to" => to }]
        steps += affected_keys.map do |key|
          { "op" => "mv", "from" => key, "to" => "#{to}#{key[from.length..]}" }
        end

        plan = Textus::Store::Jobs::Plan.new(steps: steps, warnings: [])
        return Success(plan) if dry_run

        rewrite_manifest!(geom, from:, to:)
        FileUtils.mv(geom.lane_path(from), dest_dir)
        Success(plan)
      end

      def self.rewrite_manifest!(geom, from:, to:)
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
