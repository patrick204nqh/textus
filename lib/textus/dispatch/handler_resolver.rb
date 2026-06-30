module Textus
  module Boot
    DepNotFound = Class.new(Textus::Error)
  end

  module Dispatch
    module HandlerResolver
      HANDLER_NAMESPACES = [
        Handlers::Read, Handlers::Write, Handlers::Maintenance,
      ].freeze

      module_function

      def eager_load!
        handlers_dir = File.expand_path("../../handlers", __FILE__)
        Dir[File.join(handlers_dir, "**", "*.rb")].sort.each { |f| require f }
      end

      def build(ctx, handlers: nil)
        handler_modules = handlers || discover_all
        ctx_hash = ctx.to_h

        registry = HandlerRegistry.new
        handler_modules.each do |mod|
          next unless mod.const_defined?(:HANDLES) && mod.const_defined?(:NEEDS)

          contract_class = mod::HANDLES
          needs          = mod::NEEDS

          deps_hash = needs.to_h do |field|
            unless ctx_hash.key?(field)
              raise Boot::DepNotFound.new(
                "boot_dep_not_found",
                "handler #{mod.name || mod.inspect} needs :#{field} but Ctx has no such field",
              )
            end
            [field, ctx_hash[field]]
          end

          dep_struct = Data.define(*needs).new(**deps_hash)

          registry.register(contract_class, ->(command, call) { mod.call(command, call, dep_struct) })
        end
        registry
      end

      def discover_all
        HANDLER_NAMESPACES.flat_map do |ns|
          ns.constants(false).filter_map { |c| ns.const_get(c) }.select { |v| v.is_a?(Module) }
        end
      end
    end
  end
end
