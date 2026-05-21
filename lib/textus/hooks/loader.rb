module Textus
  module Hooks
    module Loader
      THREAD_REGISTRY_KEY = :__textus_active_registry__
      private_constant :THREAD_REGISTRY_KEY

      def self.with_registry(registry)
        prev = Thread.current[THREAD_REGISTRY_KEY]
        Thread.current[THREAD_REGISTRY_KEY] = registry
        yield
      ensure
        Thread.current[THREAD_REGISTRY_KEY] = prev
      end

      def self.current_registry
        Thread.current[THREAD_REGISTRY_KEY] or
          raise UsageError.new("no active registry; hook code must be loaded by a Store")
      end
    end
  end

  # Public DSL — unchanged surface
  def self.with_registry(registry, &) = Hooks::Loader.with_registry(registry, &)
  def self.current_registry           = Hooks::Loader.current_registry
  def self.hook(event, name, **, &)   = Hooks::Loader.current_registry.register(event, name, **, &)
end
