# Produces schema-reference data (ADR 0097) from the live schema cache.
# Acquire-only (ADR 0094) — the publish template renders it.
#
# Schema identity note: Textus::Schema#name reads raw["name"] from the yaml
# body, but the dogfood schema files carry no top-level "name:" key — the
# schema's name IS the filename stem. Schemas#by_name keys on that canonical
# name, so each row's "name" matches the key used by `textus schema show <name>`.
Textus.hook do |reg|
  reg.on(:resolve_handler, :schema) do |caps:, **|
    schemas = caps.schemas.by_name.sort_by { |name, _| name }.map do |name, s|
      {
        "name" => name,
        "required" => Array(s.required).map(&:to_s).sort,
        "optional" => Array(s.optional).map(&:to_s).sort,
        "fields" => s.fields.keys.map(&:to_s).sort,
      }
    end
    { "content" => { "schemas" => schemas } }
  end
end
