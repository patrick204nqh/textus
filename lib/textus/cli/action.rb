module Textus
  class CLI
    class Action < Verb
      prepend DeprecatedAliasMixin

      def self.deprecated_name = "action"
      def self.replacement_path = "extension run"

      def parse(argv)
        @raw_argv = argv
      end

      def call(store)
        name = @raw_argv.shift
        raise UsageError.new("action requires a name") if name.nil?

        as_flag = nil
        args = {}
        @raw_argv.each do |tok|
          case tok
          when /\A--as=(.+)\z/         then as_flag = ::Regexp.last_match(1)
          when /\A--format=/           then next
          when /\A--([\w-]+)=(.*)\z/   then args[::Regexp.last_match(1)] = ::Regexp.last_match(2)
          else
            raise UsageError.new("unknown arg to 'action #{name}': #{tok}")
          end
        end

        role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
        callable = store.registry.action(name)
        view = StoreView.new(store, writable: true, as: role)

        begin
          Timeout.timeout(Textus::Refresh::ACTION_TIMEOUT_SECONDS) do
            callable.call(config: {}, store: view, args: args)
          end
        rescue Timeout::Error
          raise UsageError.new(
            "action '#{name}' exceeded #{Textus::Refresh::ACTION_TIMEOUT_SECONDS}s timeout",
          )
        rescue Textus::Error
          raise
        rescue StandardError => e
          raise UsageError.new("action '#{name}' raised: #{e.class}: #{e.message}")
        end

        emit({ "action" => name, "ok" => true })
      end
    end
  end
end
