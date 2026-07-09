module Textus
  module Protocol
    class Blueprint
      module Controller
        module_function

        def show(key, container)
          mentry = resolve_entry(key, container)
          Compiler.compile(mentry, schemas: container.schemas)
        end

        def validate(key, payload, container)
          mentry = resolve_entry(key, container)
          blueprint = Compiler.compile(mentry, schemas: container.schemas)
          errors = []

          last_seg = key.split(".").last
          if blueprint.naming
            pattern = Regexp.new(blueprint.naming[:pattern])
            unless last_seg.match?(pattern)
              errors << "naming violation: '#{last_seg}' must match #{blueprint.naming[:alias]} pattern " \
                        "(e.g. #{blueprint.naming[:example]})"
            end
          end

          if blueprint.schema
            meta = payload.meta || {}
            blueprint.schema[:fields].select { |f| f[:required] }.each do |f|
              errors << "missing required meta field: '#{f[:name]}' (#{f[:desc]})" unless meta.key?(f[:name])
            end
          end

          begin
            fmt = Format.for(blueprint.format)
            fmt.validate_raw_entry!({ "_meta" => (payload.meta || {}), "content" => payload.content }, mentry.lane)
          rescue Textus::UsageError => e
            errors << e.message
          end

          errors
        end

        def scaffold(key, container)
          blueprint = show(key, container)
          last_seg = blueprint.template[:key].split(".").last
          {
            key: blueprint.template[:key],
            body: blueprint.template[:body].sub("<body>", "# #{last_seg}\n\n"),
          }
        end

        def resolve_entry(key, container)
          container.manifest.resolver.resolve(key).entry
        end
      end
    end
  end
end
