module Textus
  class StoreView
    READ_METHODS  = %i[get list where schema_envelope deps rdeps published stale validate_all].freeze
    WRITE_METHODS = %i[put delete accept].freeze

    def initialize(store)
      @store = store
    end

    READ_METHODS.each do |m|
      define_method(m) { |*args, **kw| @store.public_send(m, *args, **kw) }
    end

    WRITE_METHODS.each do |m|
      define_method(m) { |*_args, **_kw| raise UsageError.new("StoreView is read-only") }
    end
  end
end
