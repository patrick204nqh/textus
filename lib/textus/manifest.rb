require "yaml"
require_relative "manifest/schema"
require_relative "manifest/resolver"
require_relative "manifest/role_kinds"

module Textus
  class Manifest
    attr_reader :root, :entries, :raw

    def zones
      @zones ||= Array(@raw["zones"]).to_h { |z| [z["name"], Array(z["write_policy"])] }
    end

    def zone_readers
      @zone_readers ||= Array(@raw["zones"]).to_h do |z|
        rp = z["read_policy"]
        [z["name"], rp.nil? ? :all : Array(rp)]
      end
    end

    def zone_writers(zone_name)
      zones[zone_name] or raise UsageError.new("undeclared zone '#{zone_name}'")
    end

    def permission_for(zone_name)
      Textus::Domain::Permission.new(
        zone: zone_name,
        write_policy: zone_writers(zone_name),
        read_policy: zone_readers[zone_name] || :all,
      )
    end

    def role_mapping
      @role_mapping ||= RoleKinds.resolve(@raw["roles"])
    end

    def role_kind(name)
      role_mapping[name]
    end

    def roles_with_kind(kind)
      role_mapping.each_with_object([]) { |(name, k), acc| acc << name if k == kind }
    end

    def zone_kinds(zone_name)
      writers = zone_writers(zone_name)
      writers.each_with_object(Set.new) do |w, acc|
        k = role_kind(w)
        acc << k if k
      end
    end

    def self.parse(yaml_text, root: ".")
      raw = YAML.safe_load(yaml_text, aliases: false)
      check_version!(raw, "<string>")
      new(root, raw)
    end

    def self.load(root)
      manifest_path = File.join(root, "manifest.yaml")
      raise IoError.new("manifest not found: #{manifest_path}") unless File.exist?(manifest_path)

      raw = YAML.safe_load_file(manifest_path, aliases: false)
      check_version!(raw, manifest_path)
      new(root, raw)
    end

    def self.check_version!(raw, source)
      return if raw["version"] == PROTOCOL

      raise BadFrontmatter.new(
        source,
        "unsupported manifest version #{raw["version"].inspect}; expected #{PROTOCOL.inspect}",
      )
    end
    private_class_method :check_version!

    def initialize(root, raw)
      @root = root
      @raw = raw
      raise BadFrontmatter.new(File.join(root, "manifest.yaml"), "manifest must declare zones:") if Array(raw["zones"]).empty?

      Schema.validate!(raw)

      @entries = Array(raw["entries"]).map do |e|
        entry = Manifest::Entry::Parser.call(self, e)
        Manifest::Entry::Validators.run_all(entry)
        entry
      end
      validate_declared_keys!
    end

    def rules
      @rules ||= Textus::Manifest::Rules.parse(@raw["rules"] || [])
    end

    def rules_for(key)
      rules.for(key)
    end

    def resolver
      @resolver ||= Resolver.new(self)
    end

    def validate_key!(key)
      raise UsageError.new("empty key") if key.nil? || key.empty?

      Key::Grammar.validate!(key)
    end

    private

    def validate_declared_keys!
      @entries.each { |e| validate_key!(e.key) }
    end
  end
end
