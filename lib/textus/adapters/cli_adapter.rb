require "json"

module Textus
  module Adapters
    class CliAdapter
      CLI_PATH_OVERRIDES = {
        uid: "key uid",
        key_mv_under: "key mv-under",
        key_delete_under: "key delete-under",
      }.freeze

      STDIN_ACTIONS = %i[propose put].to_set.freeze

      def initialize(api:, default_role: Textus::Value::Role::DEFAULT)
        @api = api
        @default_role = default_role
      end

      def call(argv, store_resolver: nil, stdin: $stdin, stdout: $stdout, stderr: $stderr, cwd: Dir.pwd)
        args = argv.dup

        if args.first == "init"
          return handle_init(stdout, stderr, cwd)
        end

        if args.first(2) == %w[mcp serve]
          return handle_mcp_serve(args.drop(2), store_resolver, stdin, stdout, stderr)
        end

        if args.first(2) == %w[web serve]
          return handle_web_serve(args.drop(2), store_resolver, stdout, stderr)
        end

        if args.first == "watch"
          return handle_watch(args.drop(1), store_resolver, stdout, stderr)
        end

        request = normalize(args, stdin, cwd)
        unless @api.respond_to?(request.action)
          err = Textus::UsageError.new("unknown command: #{request.action}")
          return format_response(Adapters::Response.new(payload: nil, error: err), stdout, stderr)
        end

        session = @api.open_session(role: request.role)
        begin
          response = @api.send(request.action, **request.params, session:)
          format_response(Adapters::Response.new(payload: response, error: nil), stdout, stderr)
        rescue Textus::Error => e
          format_response(Adapters::Response.new(payload: nil, error: e), stdout, stderr)
        ensure
          @api.close_session(session)
        end
      end

      def normalize(raw, stdin = $stdin, cwd = Dir.pwd)
        role_kv = raw.find { |a| a.start_with?("--as=") }
        non_flag = raw.reject { |a| a.start_with?("--") }
        raw_flags = raw.select { |a| a.start_with?("--") }

        action, positionals = resolve_action(non_flag)
        params = build_params(action, positionals, raw_flags, stdin)

        role = role_kv&.delete_prefix("--as=") || @default_role
        Request.new(action: action, params: params, role: role)
      end

      private

      def resolve_action(argv)
        action_registry = Textus::Protocol::ActionRegistry

        (1..argv.size).reverse_each do |n|
          candidate = argv.first(n).join(" ")
          action_registry.registered.each do |spec|
            path = CLI_PATH_OVERRIDES[spec.action] || spec.cli_path
            return [spec.action, argv.drop(n)] if path == candidate
          end
        end

        [argv.first&.to_sym || :help, argv.drop(1)]
      end

      def build_params(action, positionals, flags, stdin)
        spec = Textus::Protocol::ActionRegistry.for(action)
        return { positionals: positionals } unless spec

        ordered = spec.args.select(&:positional).map(&:name)
        named = {}
        ordered.zip(positionals).each { |n, v| named[n] = v if v }

        non_positional = spec.args.reject(&:positional)
        non_positional.each do |a|
          flag = flag_value(a, flags)
          named[a.name] = flag unless flag.nil?
        end

        spec.args.each do |a|
          next if named.key?(a.name) || a.cli_default.nil?
          named[a.name] = a.cli_default
        end

        if STDIN_ACTIONS.include?(action) && flags.include?("--stdin")
          raw = stdin.read.to_s.strip
          unless raw.empty?
            envelope = JSON.parse(raw)
            if envelope.key?("body") && !envelope.key?("data")
              envelope["data"] = envelope.delete("body")
            end
            spec.args.each do |a|
              named[a.name] = envelope[a.wire.to_s] if envelope.key?(a.wire.to_s)
            end
          end
        end

        fmt_idx = flags.index { |f| f.start_with?("--as-format=") }
        named[:format] = flags[fmt_idx].delete_prefix("--as-format=") if fmt_idx

        named
      end

      def flag_value(arg, flags)
        wire = arg.wire.to_s.tr("_", "-")
        if arg.type == :boolean
          return true if flags.include?("--#{wire}")
          return false if flags.include?("--no-#{wire}")
          return arg.cli_default unless arg.cli_default.nil?
          return arg.default unless arg.default.nil?
          nil
        else
          prefix = "--#{wire}="
          match = flags.find { |f| f.start_with?(prefix) }
          match ? match.delete_prefix(prefix) : nil
        end
      end

      def handle_init(stdout, stderr, cwd)
        target = File.join(cwd, ".textus")
        result = Textus::Protocol::Init.run(target, with_agent: false)
        stdout.puts(JSON.generate(result))
        0
      end

      def handle_mcp_serve(argv, store_resolver, stdin, stdout, stderr)
        role_kv = argv.find { |a| a.start_with?("--as=") }
        role = role_kv&.delete_prefix("--as=") || Textus::Value::Role::AGENT
        store = store_resolver.call.with_role(role)
        Textus::Surface::MCP::Server.new(store: store, stdin: stdin, stdout: stdout, role: role).run
        0
      end

      def handle_web_serve(argv, store_resolver, stdout, stderr)
        role_kv = argv.find { |a| a.start_with?("--as=") }
        role = role_kv&.delete_prefix("--as=") || Textus::Value::Role::AGENT
        port_idx = argv.index { |a| a.start_with?("--port=") }
        port = port_idx ? argv[port_idx].delete_prefix("--port=").to_i : 9292
        store = store_resolver.call.with_role(role)
        Textus::Surface::Web.set :textus_session, store
        Textus::Surface::Web.set :textus_gate, store.gate
        Textus::Surface::Web.set :port, port
        Textus::Surface::Web.run!
        0
      end

      def handle_watch(argv, store_resolver, stdout, stderr)
        poll_idx = argv.index { |a| a.start_with?("--poll=") }
        poll = poll_idx ? argv[poll_idx].delete_prefix("--poll=").to_f : nil
        store = store_resolver.call
        watcher = Textus::Surface::Watcher.new(container: store.container)
        watcher.run(poll: poll)
        0
      end

      def format_response(response, stdout, stderr)
        if response.success?
          stdout.puts(JSON.generate({ "protocol" => Textus::PROTOCOL }.merge(response.payload)))
          0
        else
          err = response.error
          stdout.puts(JSON.generate(err.to_envelope))
          stderr.puts("#{err.code}: #{err.message}")
          stderr.puts("  → #{err.hint}") if err.hint
          err.exit_code
        end
      end
    end
  end
end
