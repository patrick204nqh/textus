module Textus
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
      raise UsageError.new("no active registry; extension code must be loaded by a Store")
  end

  def self.action(name, &)
    current_registry.register_action(name, &)
  end

  def self.reducer(name, &)
    current_registry.register_reducer(name, &)
  end

  def self.hook(event, name, &)
    current_registry.register_hook(event, name, &)
  end

  def self.doctor_check(name, &)
    current_registry.register_doctor_check(name, &)
  end
end
