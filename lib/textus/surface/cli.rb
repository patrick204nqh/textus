require "json"
require "optparse"

module Textus
  module Surface
    class CLI
      def self.run(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr, cwd: Dir.pwd)
        new(stdin: stdin, stdout: stdout, stderr: stderr, cwd: cwd).run(argv)
      end

      def initialize(stdin:, stdout:, stderr:, cwd:)
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
        @cwd = cwd
        @root_arg = nil
      end

      def run(argv)
        @root_arg = extract_root!(argv)
        show_version = false
        show_help = false
        OptionParser.new do |o|
          o.on("--version", "-v") { show_version = true }
          o.on("--help", "-h") { show_help = true }
        end.order!(argv)

        return @stdout.puts(VERSION) || 0 if show_version
        return print_help || 0 if show_help

        adapter = Adapters::CliAdapter.new
        exit_code = adapter.call(argv,
          gate: store.gate,
          store_resolver: -> { store },
          stdin: @stdin, stdout: @stdout, stderr: @stderr, cwd: @cwd,
        )
        coerce_exit_code(exit_code)
      rescue Textus::Error => e
        emit_error(e)
      end

      private

      def extract_root!(argv)
        i = argv.index { |a| a == "--root" || a.start_with?("--root=") }
        return nil unless i

        tok = argv[i]
        if tok.start_with?("--root=")
          argv.delete_at(i)
          tok.delete_prefix("--root=")
        else
          val = argv[i + 1]
          raise UsageError.new("--root requires a PATH") if val.nil? || val.start_with?("-")

          argv.delete_at(i + 1)
          argv.delete_at(i)
          val
        end
      end

      def coerce_exit_code(value)
        case value
        when Integer then value
        when true, nil then 0
        when false then 1
        else
          @stderr.puts("warning: action returned non-Integer #{value.class}; treating as 0")
          0
        end
      end

      def store
        @store ||= Textus::Protocol::Session.open(store_root)
      end

      def store_root
        @store_root ||= explicit_root || discovered_root
      end

      def explicit_root
        @root_arg || ENV.fetch("TEXTUS_ROOT", nil)
      end

      def discovered_root
        dir = File.expand_path(@cwd)
        loop do
          if File.directory?(File.join(dir, ".textus")) && File.exist?(File.join(dir, ".textus", "manifest.yaml"))
            return File.join(dir, ".textus")
          end

          parent = File.dirname(dir)
          raise Textus::IoError.new("no .textus directory found from #{@cwd}") if parent == dir

          dir = parent
        end
      end

      def emit_error(err)
        @stdout.puts(JSON.generate(err.to_envelope))
        @stderr.puts("#{err.code}: #{err.message}")
        @stderr.puts("  → #{err.hint}") if err.hint
        err.exit_code
      end

      def print_help
        @stdout.puts <<~HELP
          textus #{VERSION} — reference implementation of #{PROTOCOL}

          Usage (json output is the default):
            textus list [--prefix=KEY] [--lane=LANE]
            textus where KEY
            textus get KEY
            textus put KEY --stdin --as=ROLE
            textus propose KEY --stdin --as=ROLE
            textus accept KEY --as=ROLE
            textus reject KEY --as=ROLE
            textus audit [--key=K] [--lane=LANE] [--role=R] [--verb=V] [--since=X] [--correlation-id=ID] [--limit=N]
            textus blame KEY [--limit=N]
            textus pulse [--since=N]
            textus boot
            textus drain [PREFIX] --as=ROLE
            textus watch
            textus key {delete,mv,mv-prefix,delete-prefix,uid}
            textus rule {explain,lint,list}
            textus session {open,close}
            textus schema {show}
            textus data {mv}
            textus mcp {serve}
        HELP
      end
    end
  end
end
