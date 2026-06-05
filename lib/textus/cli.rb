require "json"
require "optparse"

module Textus
  class CLI
    # Auto-derived verb table. Every CLI::Verb (or Group) subclass that
    # declares `command_name "X"` and has no `parent_group` is a top-level
    # verb. Sorted alphabetically for stable help output. Adding a new
    # verb requires only a new file declaring its `command_name`.
    #
    # `k.name` gates out anonymous (Class.new) subclasses: real verbs are always
    # named constants (generated Gen* or hand-authored classes), so this is a
    # no-op in production but keeps throwaway test fixtures from leaking into the
    # registry (and tripping the reconciliation guards order-dependently).
    def self.verbs
      Runner.install!
      Verb.descendants
          .select { |k| k.name && k.command_name && k.parent_group.nil? }
          .sort_by(&:command_name)
          .to_h { |k| [k.command_name, k] }
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
      # `--root` is a global, position-agnostic option: pull it out of argv
      # wherever it appears so it works uniformly before OR after any verb or
      # group (e.g. both `textus --root=X hook list` and
      # `textus hook list --root=X`). Without this, `order!` below only sees
      # options before the first verb token, so a trailing `--root` reached the
      # verb's own parser and raised InvalidOption (#161 F5). TEXTUS_ROOT already
      # works everywhere via Store.discover, so this brings the flag to parity.
      @root_arg = extract_root!(argv)

      # Define --version/--help ourselves so OptionParser doesn't intercept them
      # with its built-in handlers (which print "version unknown" and a bare usage
      # line, then exit before we ever reach the verb dispatch below).
      show_version = false
      show_help = false
      OptionParser.new do |o|
        o.on("--version", "-v") { show_version = true }
        o.on("--help", "-h") { show_help = true }
      end.order!(argv)

      return @stdout.puts(VERSION) || 0 if show_version
      return print_help || 0 if show_help

      verb = argv.shift
      raise UsageError.new("missing verb") if verb.nil?

      klass = self.class.verbs[verb] or raise UsageError.new("unknown verb: #{verb}")
      coerce_exit_code(dispatch(klass, argv))
    rescue Textus::Error => e
      emit_error(e)
    end

    private

    # Remove the first `--root=PATH` or `--root PATH` token from argv (anywhere)
    # and return its value, or nil if absent. Mutates argv in place.
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
          textus fetch KEY
          textus fetch all [--prefix=KEY] [--zone=Z]
          textus audit [--key=K] [--zone=Z] [--role=R] [--verb=V] [--since=X] [--correlation-id=ID] [--limit=N]
          textus blame KEY [--limit=N]
          textus doctor
          textus boot

          textus key {delete,mv,uid}
          textus rule {explain,lint,list}
          textus schema {diff,init,migrate,show}
          textus hook {list,run}
      HELP
    end
  end
end
