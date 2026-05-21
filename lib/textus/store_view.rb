module Textus
  class StoreView
    READ_METHODS  = %i[get list where schema_envelope deps rdeps published stale validate_all].freeze
    WRITE_METHODS = %i[put delete accept].freeze

    def initialize(store, writable: false, as: nil)
      raise UsageError.new("writable StoreView requires an as: role") if writable && (as.nil? || as.to_s.empty?)

      @store = store
      @writable = writable
      @as = as
    end

    READ_METHODS.each do |m|
      define_method(m) { |*args, **kw| @store.reader.public_send(m, *args, **kw) }
    end

    WRITE_METHODS.each do |m|
      define_method(m) do |*args, **kw|
        raise UsageError.new("StoreView is read-only") unless @writable

        kw[:as] = @as unless kw.key?(:as)
        @store.public_send(m, *args, **kw)
      end
    end
  end
end
