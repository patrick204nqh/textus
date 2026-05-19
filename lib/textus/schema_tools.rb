require "yaml"
require "fileutils"

module Textus
  module SchemaTools
    # textus schema-init NAME --from=KEY  → infer YAML schema from an entry's frontmatter
    def self.init(store, name:, from:)
      env = store.get(from)
      fm = env["frontmatter"]
      schema = {
        "name" => name,
        "required" => fm.keys,
        "optional" => [],
        "fields" => fm.each_with_object({}) { |(k, v), h| h[k] = { "type" => infer_type(v) } },
      }
      FileUtils.mkdir_p(File.join(store.root, "schemas"))
      target = File.join(store.root, "schemas", "#{name}.yaml")
      File.write(target, YAML.dump(schema))
      { "protocol" => PROTOCOL, "schema_name" => name, "path" => target }
    end

    # textus schema-diff NAME  → list keys whose frontmatter violates the schema
    def self.diff(store, name:)
      schema = load_schema(store, name)
      drift = []
      store.manifest.enumerate.each do |row|
        env = store.get(row[:key])
        begin
          schema.validate!(env["frontmatter"])
        rescue SchemaViolation => e
          drift << { "key" => row[:key], "details" => e.details }
        end
      end
      { "protocol" => PROTOCOL, "schema_name" => name, "drift" => drift }
    end

    # textus schema-migrate NAME --rename=OLD:NEW → rewrites frontmatter across affected entries
    def self.migrate(store, name:, rename:)
      old_field, new_field = rename.split(":", 2)
      raise UsageError.new("--rename=OLD:NEW") unless old_field && new_field && !new_field.empty?
      touched = []
      store.manifest.enumerate.each do |row|
        env = store.get(row[:key])
        fm = env["frontmatter"]
        next unless fm.key?(old_field)
        fm[new_field] = fm.delete(old_field)
        store.put(row[:key], frontmatter: fm, body: env["body"], as: "human")
        touched << row[:key]
      end
      { "protocol" => PROTOCOL, "migrated" => touched }
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

    def self.load_schema(store, name)
      store.schema_for(name)
    rescue IoError
      raise UsageError.new("schema not found: #{name}")
    end
  end
end
