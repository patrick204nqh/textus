require "json"
require "optparse"
require "time"
require "timeout"
require "yaml"

module Textus
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

    def run(argv) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/AbcSize
      OptionParser.new do |o|
        o.on("--root=PATH") { |v| @root_arg = v }
      end.order!(argv)
      verb = argv.shift
      raise UsageError.new("missing verb") if verb.nil?

      case verb
      when "list"   then dispatch(List, argv)
      when "where"  then dispatch(Where, argv)
      when "get"    then dispatch(Get, argv)
      when "put"    then verb_put(argv)
      when "schema" then dispatch(Schema, argv)
      when "stale"  then dispatch(Stale, argv)
      when "delete"       then dispatch(Delete, argv)
      when "build"        then dispatch(Build, argv)
      when "deps"         then dispatch(Deps, argv)
      when "rdeps"        then dispatch(Rdeps, argv)
      when "published"    then dispatch(Published, argv)
      when "accept"       then dispatch(Accept, argv)
      when "init"         then dispatch(InitVerb, argv)
      when "schema-init"    then dispatch(SchemaInit, argv)
      when "schema-diff"    then verb_schema_diff(argv)
      when "schema-migrate" then verb_schema_migrate(argv)
      when "action"         then verb_action(argv)
      when "refresh"        then dispatch(RefreshVerb, argv)
      when "extensions"     then verb_extensions(argv)
      when "migrate-keys"   then verb_migrate_keys(argv)
      when "mv"             then verb_mv(argv)
      when "uid"            then dispatch(Uid, argv)
      when "doctor"         then dispatch(DoctorVerb, argv)
      when "intro"          then dispatch(IntroVerb, argv)
      when "--version", "-v" then @stdout.puts(VERSION)
                                  0
      when "--help", "-h"    then print_help
                                  0
      else raise UsageError.new("unknown verb: #{verb}")
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

    def parse_format!(argv)
      fmt = "json"
      OptionParser.new do |o|
        o.on("--format=FMT") { |v| fmt = v }
      end.permute!(argv)
      raise UsageError.new("only --format=json is supported in v1") unless fmt == "json"

      fmt
    end

    def parse_prefix!(argv)
      prefix = nil
      OptionParser.new do |o|
        o.on("--prefix=KEY") { |v| prefix = v }
        o.on("--zone=Z") {}
        o.on("--format=FMT") {}
      end.permute!(argv)
      prefix
    end

    def parse_prefix_and_zone!(argv)
      prefix = nil
      zone = nil
      fmt = "json"
      OptionParser.new do |o|
        o.on("--prefix=KEY") { |v| prefix = v }
        o.on("--zone=Z") { |v| zone = v }
        o.on("--format=FMT") { |v| fmt = v }
      end.permute!(argv)
      raise UsageError.new("only --format=json is supported in v1") unless fmt == "json"

      [prefix, zone]
    end

    def verb_put(argv) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      key = argv.shift or raise UsageError.new("put requires a key")
      as_flag = nil
      use_stdin = false
      action_name = nil
      OptionParser.new do |o|
        o.on("--stdin") { use_stdin = true }
        o.on("--as=ROLE") { |v| as_flag = v }
        o.on("--action=NAME") { |v| action_name = v }
        o.on("--format=FMT") {}
      end.permute!(argv)
      raise UsageError.new("put requires --stdin in v1") unless use_stdin

      role = Role.resolve(flag: as_flag, env: ENV, root: store.root)

      raw = @stdin.read
      payload =
        if action_name
          callable = store.registry.action(action_name)
          result =
            begin
              Timeout.timeout(Textus::Refresh::ACTION_TIMEOUT_SECONDS) do
                callable.call(config: { "bytes" => raw }, store: Textus::StoreView.new(store), args: {})
              end
            rescue Timeout::Error
              raise UsageError.new(
                "action '#{action_name}' exceeded #{Textus::Refresh::ACTION_TIMEOUT_SECONDS}s timeout",
              )
            end
          basename = key.split(".").last
          {
            "frontmatter" => {
              "name" => basename,
              "last_refreshed_at" => Time.now.utc.iso8601,
              "actioned_with" => action_name,
            }.merge(result[:frontmatter] || result["frontmatter"] || {}),
            "body" => result[:body] || result["body"] || "",
          }
        else
          JSON.parse(raw)
        end

      fm = payload["frontmatter"] || {}
      body = payload["body"] || ""
      if_etag = payload["if_etag"]
      emit(store.put(key, frontmatter: fm, body: body, if_etag: if_etag, as: role))
    end

    def verb_schema_diff(argv)
      name = argv.shift or raise UsageError.new("schema-diff NAME")
      parse_format!(argv)
      emit(Textus::SchemaTools.diff(store, name: name))
    end

    def verb_schema_migrate(argv)
      name = argv.shift or raise UsageError.new("schema-migrate NAME")
      rename = nil
      OptionParser.new do |o|
        o.on("--rename=O:N") { |v| rename = v }
        o.on("--format=FMT") {}
      end.permute!(argv)
      raise UsageError.new("schema-migrate requires --rename=OLD:NEW") unless rename

      emit(Textus::SchemaTools.migrate(store, name: name, rename: rename))
    end

    def verb_action(argv)
      name = argv.shift
      raise UsageError.new("action requires a name") if name.nil?

      as_flag = nil
      args = {}
      argv.each do |tok|
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

      emit({ "protocol" => Textus::PROTOCOL, "action" => name, "ok" => true })
    end

    def verb_extensions(argv) # rubocop:disable Metrics/AbcSize
      subcommand = argv.shift
      raise UsageError.new("extensions requires 'list'") unless subcommand == "list"

      kind = nil
      OptionParser.new do |o|
        o.on("--kind=K") { |v| kind = v }
        o.on("--format=FMT") {}
      end.permute!(argv)

      rows = []
      rows += store.registry.action_names.map { |n| { "kind" => "action", "name" => n.to_s } }
      rows += store.registry.doctor_check_names.map { |n| { "kind" => "doctor_check", "name" => n.to_s } }
      rows += store.registry.reducer_names.map { |n| { "kind" => "reducer", "name" => n.to_s } }
      store.registry.hook_events.each do |evt|
        store.registry.hooks(evt).each do |h|
          rows << { "kind" => "hook", "event" => evt.to_s, "name" => h[:name].to_s }
        end
      end
      store.manifest.entries.each do |e|
        e.events.each do |evt, defs|
          Array(defs).each do |defn|
            next unless defn["exec"]

            rows << {
              "kind" => "hook", "event" => evt.to_s, "exec" => defn["exec"],
              "key" => e.key, "as" => defn["as"] || "script"
            }
          end
        end
      end
      rows.select! { |r| r["kind"] == kind } if kind

      emit({ "protocol" => Textus::PROTOCOL, "extensions" => rows })
    end

    def verb_migrate_keys(argv)
      write = false
      OptionParser.new do |o|
        o.on("--dry-run") { write = false }
        o.on("--write")   { write = true }
        o.on("--format=FMT") {}
      end.permute!(argv)
      res = Textus::MigrateKeys.run(store, write: write)
      @stdout.puts(JSON.generate(res))
      res["ok"] ? 0 : 1
    end

    def verb_mv(argv)
      old_key = argv.shift or raise UsageError.new("mv requires <old-key> <new-key>")
      new_key = argv.shift or raise UsageError.new("mv requires <old-key> <new-key>")
      as_flag = nil
      dry_run = false
      OptionParser.new do |o|
        o.on("--as=ROLE") { |v| as_flag = v }
        o.on("--dry-run") { dry_run = true }
        o.on("--format=FMT") {}
      end.permute!(argv)
      role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
      emit(store.mv(old_key, new_key, as: role, dry_run: dry_run))
    end

    def emit(obj)
      @stdout.puts(JSON.generate(obj))
      0
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
