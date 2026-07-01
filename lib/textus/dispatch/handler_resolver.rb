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

        registry = HandlerRegistry.new
        handler_modules.each do |mod|
          next unless mod.const_defined?(:HANDLES) && mod.const_defined?(:NEEDS)

          contract_classes = [mod::HANDLES]
          needs = mod::NEEDS

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

          contract_classes.each do |contract_class|
            registry.register(contract_class, ->(command:, call:) { mod.call(command, call, dep_struct) })
          end
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
