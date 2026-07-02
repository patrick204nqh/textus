module Textus
  module Boot
    class DepNotFound < Textus::Error
    end
  end

  module Dispatch
    module HandlerResolver
      module_function

      def eager_load!
        Dir[File.expand_path("../../use_cases/**/*.rb", __dir__)].each { |f| require f }
      end

      def build(ctx, handlers: nil)
        handler_modules = handlers || discover_all
        ctx_hash = ctx.to_h

        registry = {}
        handler_modules.each do |mod|
          contract_class = if mod.respond_to?(:handles_contract)
                             mod.handles_contract
                           else
                             mod::HANDLES if mod.const_defined?(:HANDLES)
                           end
          needs = if mod.respond_to?(:needs_fields)
                    mod.needs_fields
                  else
                    mod::NEEDS if mod.const_defined?(:NEEDS)
                  end
          next unless contract_class && needs

          deps_hash = needs.to_h do |field|
            unless ctx_hash.key?(field)
              raise Boot::DepNotFound.new(
                "boot_dep_not_found",
                "handler #{mod.name || mod.inspect} needs :#{field} but Infrastructure has no such field",
              )
            end
            [field, ctx_hash[field]]
          end

          dep_struct = Data.define(*needs).new(**deps_hash)

          registry[contract_class] = ->(command:, call:) { mod.call(command, call, dep_struct) }
        end
        registry
      end

      def discover_all
        [Textus::UseCases::Read, Textus::UseCases::Write, Textus::UseCases::Ops].flat_map do |ns|
          ns.constants(false).filter_map { |c| ns.const_get(c) }.grep(Module)
        end
      end
    end
  end
end
