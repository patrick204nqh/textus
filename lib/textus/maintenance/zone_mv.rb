require "yaml"

module Textus
  module Maintenance
    # Rename a zone — rewrites the manifest's zones[] entry, rewrites
    # the `zone:` field on every entry under the old zone, and moves
    # every file from zones/<old>/ to zones/<new>/.
    class ZoneMv
      extend Textus::Contract::DSL

      verb     :zone_mv
      summary  "Rename a zone — manifest + files. Refuses if destination exists."
      surfaces :cli, :ruby, :mcp
      cli      "zone mv"
      arg :from,    String, required: true, positional: true, description: "current zone name"
      arg :to,      String, required: true, positional: true, description: "new zone name; refused if a zone by this name already exists"
      arg :dry_run, :boolean, default: false,
                              description: "when true, returns the planned zone move without applying it; " \
                                           "defaults to false, so omitting it applies the move immediately"
      view { |v, _i| v.to_h }

      def initialize(container:, call:)
        @container = container
        @call      = call
        @manifest  = container.manifest
        @root      = container.root
      end

      def call(from, to, dry_run: false)
        raise UsageError.new("from and to required") if from.nil? || to.nil? || from.empty? || to.empty?
        raise UsageError.new("zone '#{from}' not declared") unless @manifest.data.declared_zone_kinds.key?(from)

        dest_dir = File.join(@root, "zones", to)
        raise UsageError.new("destination 'zones/#{to}' already exists") if File.exist?(dest_dir)

        affected_keys = @manifest.data.entries.select { |e| e.zone == from }.map(&:key)

        steps  = [{ "op" => "rename_zone", "from" => from, "to" => to }]
        steps += affected_keys.map { |k| { "op" => "mv", "from" => k, "to" => "#{to}#{k[from.length..]}" } }

        plan = Plan.new(steps: steps, warnings: [])
        return plan if dry_run

        rewrite_manifest!(from, to)
        FileUtils.mv(File.join(@root, "zones", from), dest_dir)
        plan
      end

      private

      def rewrite_manifest!(from, to)
        path = File.join(@root, "manifest.yaml")
        raw = YAML.safe_load_file(path, permitted_classes: [Symbol], aliases: false)
        raw["zones"].each { |z| z["name"] = to if z["name"] == from }
        raw["entries"].each do |e|
          e["zone"] = to if e["zone"] == from
          e["key"]  = e["key"].sub(/\A#{Regexp.escape(from)}(\.|\z)/, "#{to}\\1")
          e["path"] = e["path"].sub(%r{\A#{Regexp.escape(from)}(/|\z)}, "#{to}\\1")
        end
        File.write(path, YAML.dump(raw))
      end
    end
  end
end
