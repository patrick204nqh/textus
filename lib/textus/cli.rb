require "json"
require "optparse"

module Textus
  class CLI
    # verb name → Verb subclass. Adding a new verb is a one-line entry here
    # plus a new file under lib/textus/cli/.
    VERBS = {
      "accept" => Accept,
      "action" => Action,
      "build" => Build,
      "delete" => Delete,
      "deps" => Deps,
      "doctor" => DoctorVerb,
      "extensions" => Extensions,
      "get" => Get,
      "init" => InitVerb,
      "intro" => IntroVerb,
      "list" => List,
      "migrate-keys" => MigrateKeysVerb,
      "mv" => Mv,
      "published" => Published,
      "put" => Put,
      "rdeps" => Rdeps,
      "refresh" => RefreshVerb,
      "schema" => SchemaVerb,
      "schema-diff" => SchemaDiff,
      "schema-init" => SchemaInit,
      "schema-migrate" => SchemaMigrate,
      "stale" => Stale,
      "uid" => Uid,
      "where" => Where,
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
          textus put KEY --stdin [--action=NAME] --as=ROLE
          textus schema KEY
          textus stale [--prefix=KEY] [--zone=Z]
          textus action NAME [--key=val ...] [--as=ROLE]
          textus doctor
          textus intro
      HELP
    end
  end
end
