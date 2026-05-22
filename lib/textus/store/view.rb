module Textus
  class Store
    # Deprecated as of 0.9.1: use Textus::Application::Context instead.
    # Removal scheduled for 0.10.0.
    class View
      def self.new(store, writable: false, as: nil)
        unless @warned_once
          warn "[textus] Store::View is deprecated; use Application::Context (will be removed in 0.10.0)"
          @warned_once = true
        end

        raise UsageError.new("writable Store::View requires an as: role") if writable && (as.nil? || as.to_s.empty?)

        Textus::Application::Context.new(store: store, role: as || "human")
      end
    end
  end
end
