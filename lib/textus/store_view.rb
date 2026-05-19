module Textus
  class StoreView
    READ_METHODS = %i[get list where schema_envelope deps rdeps published stale validate_all].freeze

    def initialize(store)
      @store = store
    end

    READ_METHODS.each do |m|
      define_method(m) { |*args, **kw| @store.public_send(m, *args, **kw) }
    end

    def put(*) = raise UsageError.new("StoreView is read-only; extension code may not write")
    def delete(*) = raise UsageError.new("StoreView is read-only; extension code may not write")
    def accept(*) = raise UsageError.new("StoreView is read-only; extension code may not write")
  end
end
