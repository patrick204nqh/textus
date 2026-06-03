require "yaml"
require "fileutils"

module Textus
  class Schema
    module Tools
      # textus schema init NAME --from=KEY  → infer YAML schema from an entry's frontmatter
      def self.init(store, name:, from:)
        env = pure_get(store, Textus::Role::DEFAULT, from)
        meta = env.meta
        schema = {
          "name" => name,
          "required" => meta.keys,
          "optional" => [],
          "fields" => meta.each_with_object({}) { |(k, v), h| h[k] = { "type" => infer_type(v) } },
        }
        FileUtils.mkdir_p(File.join(store.root, "schemas"))
        target = File.join(store.root, "schemas", "#{name}.yaml")
        File.write(target, YAML.dump(schema))
        { "protocol" => PROTOCOL, "schema_name" => name, "path" => target }
      end

      # textus schema diff NAME  → list keys whose frontmatter violates the schema
      def self.diff(store, name:)
        schema = load_schema(store, name)
        drift = []
        store.manifest.resolver.enumerate.each do |row|
          env = pure_get(store, Textus::Role::DEFAULT, row[:key])
          begin
            schema.validate!(env.meta)
          rescue SchemaViolation => e
            drift << { "key" => row[:key], "details" => e.details }
          end
        end
        { "protocol" => PROTOCOL, "schema_name" => name, "drift" => drift }
      end

      # textus schema migrate NAME --rename=OLD:NEW → rewrites frontmatter across affected entries
      # If --rename is omitted, falls back to schema.evolution.migrate_from.
      def self.migrate(store, name:, rename: nil)
        renames =
          if rename
            old_field, new_field = rename.split(":", 2)
            raise UsageError.new("--rename=OLD:NEW") unless old_field && new_field && !new_field.empty?

            { old_field => new_field }
          else
            load_schema(store, name).evolution["migrate_from"] || {}
          end
        raise UsageError.new("schema migrate needs --rename=OLD:NEW or schema.evolution.migrate_from") if renames.empty?

        authority = accept_role_for(store)
        ops = store.as(authority)
        touched = []
        store.manifest.resolver.enumerate.each do |row|
          env = pure_get(store, authority, row[:key])
          meta = env.meta.dup
          changed = false
          renames.each do |old, new|
            if meta.key?(old)
              meta[new] = meta.delete(old)
              changed = true
            end
          end
          next unless changed

          ops.put(row[:key], meta: meta, body: env.body)
          touched << row[:key]
        end
        { "protocol" => PROTOCOL, "migrated" => touched, "renames" => renames }
      end

      def self.infer_type(value)
        case value
        when String  then "string"
        when Numeric then "number"
        when true, false then "boolean"
        when Array   then "array"
        when Hash    then "object"
        else "string"
        end
      end

      # Orchestrator-free read: schema tooling must never trigger a fetch
      # while inspecting/migrating entries (ADR 0062).
      def self.pure_get(store, role, key)
        Textus::Read::Get.new(
          container: store.as(role).container,
          call: Textus::Call.build(role: role),
        ).call(key)
      end

      def self.load_schema(store, name)
        store.schemas.fetch(name)
      rescue IoError
        raise UsageError.new("schema not found: #{name}")
      end

      def self.accept_role_for(store)
        authority = store.manifest.policy.roles_with_capability("author").first
        return authority if authority

        raise UsageError.new(
          "schema migrate requires a role holding the 'author' capability; " \
          "none declared (add e.g. `- { name: owner, can: [author] }` to roles:)",
        )
      end
    end
  end
end
