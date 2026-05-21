require "json"
require "optparse"

module Textus
  class CLI
    # verb name → Verb subclass. Adding a new verb is a one-line entry here
    # plus a new file under lib/textus/cli/.
    VERBS = {
      "accept" => Verb::Accept,
      "reject" => Verb::Reject,
      "build" => Verb::Build,
      "delete" => Verb::Delete,
      "deps" => Verb::Deps,
      "doctor" => Verb::Doctor,
      "get" => Verb::Get,
      "hook" => Group::Hook,
      "init" => Verb::Init,
      "intro" => Verb::Intro,
      "key" => Group::Key,
      "list" => Verb::List,
      "published" => Verb::Published,
      "put" => Verb::Put,
      "rdeps" => Verb::Rdeps,
      "refresh" => Verb::Refresh,
      "schema" => Group::Schema,
      "stale" => Verb::Stale,
      "where" => Verb::Where,
    }.freeze

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

      case verb
      when "--version", "-v" then @stdout.puts(VERSION)
                                  0
      when "--help", "-h"    then print_help
                                  0
      else
        klass = VERBS[verb] or raise UsageError.new("unknown verb: #{verb}")
        dispatch(klass, argv)
      end
    rescue Textus::Error => e
      emit_error(e)
    end

    private

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

        Usage (json output is the default; --format=json accepted for back-compat):
          textus list [--prefix=KEY] [--zone=Z]
          textus where KEY
          textus get KEY
          textus put KEY --stdin [--fetch=NAME] --as=ROLE
          textus stale [--prefix=KEY] [--zone=Z]
          textus doctor
          textus intro

          textus key {mv,uid,migrate}
          textus schema {show,init,diff,migrate}
          textus hook {list,run}
      HELP
    end
  end
end
