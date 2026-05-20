module Textus
  class ExtensionRegistry
    EVENTS = %i[put delete refresh build accept].freeze

    def initialize
      @fetchers = {}
      @reducers = {}
      @hooks = {}
      @doctor_checks = {}
    end

    def register_fetcher(name, &blk)
      name = name.to_sym
      raise UsageError.new("fetcher '#{name}' already registered") if @fetchers.key?(name)

      @fetchers[name] = blk
    end

    def register_reducer(name, &blk)
      name = name.to_sym
      raise UsageError.new("reducer '#{name}' already registered") if @reducers.key?(name)

      @reducers[name] = blk
    end

    def register_hook(event, name, &blk)
      event = event.to_sym
      raise UsageError.new("unknown event: #{event}") unless EVENTS.include?(event)

      (@hooks[event] ||= []) << { name: name.to_sym, callable: blk }
    end

    def register_doctor_check(name, &blk)
      name = name.to_sym
      raise UsageError.new("doctor_check '#{name}' already registered") if @doctor_checks.key?(name)

      @doctor_checks[name] = blk
    end

    def fetcher(name)
      @fetchers[name.to_sym] or raise UsageError.new("unknown fetcher: #{name}")
    end

    def reducer(name)
      @reducers[name.to_sym] or raise UsageError.new("unknown reducer: #{name}")
    end

    def hooks(event)
      @hooks[event.to_sym] || []
    end

    def doctor_check(name)
      @doctor_checks[name.to_sym] or raise UsageError.new("unknown doctor_check: #{name}")
    end

    def doctor_check_names = @doctor_checks.keys

    def fetcher_names = @fetchers.keys
    def reducer_names = @reducers.keys
    def hook_events   = @hooks.keys
  end
end
