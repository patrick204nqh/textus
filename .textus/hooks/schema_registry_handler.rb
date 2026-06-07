# Produces schema-reference data (ADR 0097) from the live schema cache.
# Acquire-only (ADR 0094) — the publish template renders it.
#
# Schema identity note: Textus::Schema#name reads raw["name"] from the yaml
# body, but the dogfood schema files carry no top-level "name:" key — the
# schema's name IS the filename stem. Schemas#by_name keys on that canonical
# name, so each row's "name" matches the key used by `textus schema show <name>`.
# Required-ness lives in two shapes across schemas: a top-level `required:`
# list, OR a per-field `required: true` flag (the dogfood schemas use the
# latter). We render one field table per schema, normalizing both shapes into
# a per-field `required` boolean and surfacing type + maintained_by.
Textus.hook do |reg|
  reg.on(:resolve_handler, :schema) do |caps:, **|
    schemas = caps.schemas.by_name.sort_by { |name, _| name }.map do |name, s|
      top_required = Array(s.required).map(&:to_s)
      fields = s.fields.sort.map do |fname, spec|
        spec = spec.is_a?(Hash) ? spec : {}
        required = spec.key?("required") ? !!spec["required"] : top_required.include?(fname.to_s)
        {
          "name" => fname.to_s,
          "type" => spec["type"].to_s,
          "required" => required,
          "maintained_by" => spec["maintained_by"].to_s,
        }
      end
      { "name" => name, "fields" => fields }
    end
    { "content" => { "schemas" => schemas } }
  end
end
