module Textus
  THREAD_REGISTRY_KEY = :__textus_active_registry__

  def self.with_registry(registry)
    prev = Thread.current[THREAD_REGISTRY_KEY]
    Thread.current[THREAD_REGISTRY_KEY] = registry
    yield
  ensure
    Thread.current[THREAD_REGISTRY_KEY] = prev
  end

  def self.current_registry
    Thread.current[THREAD_REGISTRY_KEY] or
      raise UsageError.new("no active registry; extension code must be loaded by a Store")
  end

  def self.fetcher(name, &)
    current_registry.register_fetcher(name, &)
  end

  def self.reducer(name, &)
    current_registry.register_reducer(name, &)
  end

  def self.hook(event, name, &)
    current_registry.register_hook(event, name, &)
  end
end
