require "json"
require "optparse"

module Textus
  class CLI
    # Auto-derived verb table. Every CLI::Verb (or Group) subclass that
    # declares `command_name "X"` and has no `parent_group` is a top-level
    # verb. Sorted alphabetically for stable help output. Adding a new
    # verb requires only a new file declaring its `command_name`.
    def self.verbs
      Verb.descendants
          .select { |k| k.command_name && k.parent_group.nil? }
          .sort_by(&:command_name)
          .to_h { |k| [k.command_name, k] }
    end

    # Backward-compat constant; callers should prefer `CLI.verbs`.
    def self.const_missing(name)
      return verbs.freeze if name == :VERBS

      super
    end

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
      OptionParser.new { |o| o.on("--root=PATH") { |v| @root_arg = v } }.order!(argv)
      verb = argv.shift
      raise UsageError.new("missing verb") if verb.nil?

      result =
        case verb
        when "--version", "-v" then @stdout.puts(VERSION)
                                    0
        when "--help", "-h"    then print_help
                                    0
        else
          klass = self.class.verbs[verb] or raise UsageError.new("unknown verb: #{verb}")
          dispatch(klass, argv)
        end

      coerce_exit_code(result)
    rescue Textus::Error => e
      emit_error(e)
    end

    private

    def coerce_exit_code(value)
      case value
      when Integer then value
      when true, nil then 0
      when false then 1
      else
        @stderr.puts("warning: verb returned non-Integer #{value.class}; treating as 0")
        0
      end
    end

    def store
      @store ||= Store.discover(@cwd, root: @root_arg)
    end

    def dispatch(klass, argv)
      v = klass.new(stdin: @stdin, stdout: @stdout, stderr: @stderr, cwd: @cwd)
      v.parse(argv)
      v.call(klass.needs_store? ? store : nil)
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
          textus list [--prefix=KEY] [--zone=Z]
          textus where KEY
          textus get KEY
          textus put KEY --stdin [--fetch=NAME] --as=ROLE
          textus freshness [--prefix=KEY] [--zone=Z]
          textus refresh KEY
          textus refresh stale [--prefix=KEY] [--zone=Z]
          textus audit [--key=K] [--zone=Z] [--role=R] [--verb=V] [--since=X] [--correlation-id=ID] [--limit=N]
          textus blame KEY [--limit=N]
          textus doctor
          textus intro

          textus key {mv,uid,normalize}
          textus rule {list,explain}
          textus schema {show,init,diff,migrate}
          textus hook {list,run}
      HELP
    end
  end
end
