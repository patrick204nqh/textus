Textus.workflow "schema" do
  match "artifacts.schema"

  step :build do |_, ctx|
    schemas = ctx.container.schemas.by_name.sort_by { |name, _| name }.map do |name, s|
      top_required = Array(s.required).map(&:to_s)
      fields = s.fields.sort.map do |fname, fspec|
        fs       = fspec.is_a?(Hash) ? fspec : {}
        required = fs.key?("required") ? fs["required"] == true : top_required.include?(fname.to_s)
        { "name" => fname.to_s, "type" => fs["type"].to_s, "required" => required,
          "maintained_by" => fs["maintained_by"].to_s }
      end
      { "name" => name, "fields" => fields }
    end
    { "content" => { "schemas" => schemas } }
  end

  publish
end
