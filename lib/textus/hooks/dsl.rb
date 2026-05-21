module Textus
  module Hooks
    module Dsl
      def fetch(name, **, &) = Loader.current_registry.register(:fetch, name.to_sym, **, &)
    end
  end
end
