module Textus
  class LazyContainer
    def initialize(&factory)
      @factory = factory
      @mutex = Mutex.new
      @resolved = nil
    end

    def respond_to_missing?(name, include_private = false)
      resolve.respond_to?(name, include_private)
    end

    private

    def method_missing(name, *args, **kwargs, &block)
      resolve.public_send(name, *args, **kwargs, &block)
    end

    def resolve
      return @resolved if @resolved

      @mutex.synchronize do
        @resolved ||= @factory.call
      end
    end
  end
end
