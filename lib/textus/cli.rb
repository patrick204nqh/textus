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
    end

    def run(argv) # rubocop:disable Metrics/CyclomaticComplexity
      verb = argv.shift
      raise UsageError.new("missing verb") if verb.nil?

      case verb
      when "list"   then verb_list(argv)
      when "where"  then verb_where(argv)
      when "get"    then verb_get(argv)
      when "put"    then verb_put(argv)
      when "schema" then verb_schema(argv)
      when "stale"  then verb_stale(argv)
      when "delete"       then verb_delete(argv)
      when "validate-all" then verb_validate_all(argv)
      when "build"        then verb_build(argv)
      when "deps"         then verb_deps(argv)
      when "rdeps"        then verb_rdeps(argv)
      when "published"    then verb_published(argv)
      when "accept"       then verb_accept(argv)
      when "init"         then verb_init(argv)
      when "schema-init"    then verb_schema_init(argv)
      when "schema-diff"    then verb_schema_diff(argv)
      when "schema-migrate" then verb_schema_migrate(argv)
      when "refresh"        then verb_refresh(argv)
      when "extensions"     then verb_extensions(argv)
      when "migrate-keys"   then verb_migrate_keys(argv)
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
      @store ||= Store.discover(@cwd)
    end

    def parse_format!(argv)
      fmt = "text"
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
      fmt = "text"
      OptionParser.new do |o|
        o.on("--prefix=KEY") { |v| prefix = v }
        o.on("--zone=Z") { |v| zone = v }
        o.on("--format=FMT") { |v| fmt = v }
      end.permute!(argv)
      raise UsageError.new("only --format=json is supported in v1") unless fmt == "json"

      [prefix, zone]
    end

    def verb_list(argv)
      prefix, zone = parse_prefix_and_zone!(argv)
      emit({ "protocol" => PROTOCOL, "entries" => store.list(prefix: prefix, zone: zone) })
    end

    def verb_where(argv)
      key = argv.shift or raise UsageError.new("where requires a key")
      parse_format!(argv)
      emit(store.where(key))
    end

    def verb_get(argv)
      key = argv.shift or raise UsageError.new("get requires a key")
      parse_format!(argv)
      emit(store.get(key))
    end

    def verb_schema(argv)
      key = argv.shift or raise UsageError.new("schema requires a key")
      parse_format!(argv)
      emit(store.schema_envelope(key))
    end

    def verb_stale(argv)
      prefix, zone = parse_prefix_and_zone!(argv)
      emit(store.stale(prefix: prefix, zone: zone))
    end

    def verb_put(argv) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      key = argv.shift or raise UsageError.new("put requires a key")
      as_flag = nil
      use_stdin = false
      fetcher_name = nil
      OptionParser.new do |o|
        o.on("--stdin") { use_stdin = true }
        o.on("--as=ROLE") { |v| as_flag = v }
        o.on("--fetcher=NAME") { |v| fetcher_name = v }
        o.on("--format=FMT") {}
      end.permute!(argv)
      raise UsageError.new("put requires --stdin in v1") unless use_stdin

      role = Role.resolve(flag: as_flag, env: ENV, root: store.root)

      raw = @stdin.read
      payload =
        if fetcher_name
          callable = store.registry.fetcher(fetcher_name)
          result =
            begin
              Timeout.timeout(Textus::Refresh::FETCHER_TIMEOUT_SECONDS) do
                callable.call(config: { "bytes" => raw }, store: Textus::StoreView.new(store))
              end
            rescue Timeout::Error
              raise UsageError.new(
                "fetcher '#{fetcher_name}' exceeded #{Textus::Refresh::FETCHER_TIMEOUT_SECONDS}s timeout",
              )
            end
          basename = key.split(".").last
          {
            "frontmatter" => {
              "name" => basename,
              "last_refreshed_at" => Time.now.utc.iso8601,
              "fetched_with" => fetcher_name,
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

    def verb_delete(argv)
      key = argv.shift or raise UsageError.new("delete requires a key")
      as_flag = nil
      if_etag = nil
      OptionParser.new do |o|
        o.on("--as=ROLE") { |v| as_flag = v }
        o.on("--if-etag=E") { |v| if_etag = v }
        o.on("--format=FMT") {}
      end.permute!(argv)
      role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
      emit(store.delete(key, if_etag: if_etag, as: role))
    end

    def verb_validate_all(argv)
      parse_format!(argv)
      res = store.validate_all
      @stdout.puts(JSON.generate(res))
      res["ok"] ? 0 : 1
    end

    def verb_build(argv)
      prefix = nil
      OptionParser.new do |o|
        o.on("--prefix=K") { |v| prefix = v }
        o.on("--format=FMT") {}
      end.permute!(argv)
      res = Textus::Builder.new(store).build(prefix: prefix)
      @stdout.puts(JSON.generate(res))
      0
    end

    def verb_deps(argv)
      key = argv.shift or raise UsageError.new("deps requires a key")
      parse_format!(argv)
      emit({ "protocol" => Textus::PROTOCOL, "key" => key, "deps" => store.deps(key) })
    end

    def verb_rdeps(argv)
      key = argv.shift or raise UsageError.new("rdeps requires a key")
      parse_format!(argv)
      emit({ "protocol" => Textus::PROTOCOL, "key" => key, "rdeps" => store.rdeps(key) })
    end

    def verb_schema_init(argv)
      name = argv.shift or raise UsageError.new("schema-init NAME")
      from_key = nil
      OptionParser.new do |o|
        o.on("--from=KEY") { |v| from_key = v }
        o.on("--format=FMT") {}
      end.permute!(argv)
      raise UsageError.new("schema-init requires --from=KEY") unless from_key

      emit(Textus::SchemaTools.init(store, name: name, from: from_key))
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

    def verb_init(argv)
      OptionParser.new do |o|
        o.on("--format=FMT") {}
      end.permute!(argv)
      target = File.join(@cwd, ".textus")
      res = Textus::Init.run(target)
      @stdout.puts(JSON.generate(res))
      0
    end

    def verb_accept(argv)
      key = argv.shift or raise UsageError.new("accept requires a key")
      as_flag = nil
      OptionParser.new do |o|
        o.on("--as=ROLE") { |v| as_flag = v }
        o.on("--format=FMT") {}
      end.permute!(argv)
      role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
      emit(store.accept(key, as: role))
    end

    def verb_refresh(argv)
      key = argv.shift or raise UsageError.new("refresh requires a key")
      as_flag = nil
      OptionParser.new do |o|
        o.on("--as=ROLE") { |v| as_flag = v }
        o.on("--format=FMT") {}
      end.permute!(argv)
      role = Role.resolve(flag: as_flag, env: ENV, root: store.root)
      emit(Textus::Refresh.call(store, key, as: role))
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
      rows += store.registry.fetcher_names.map { |n| { "kind" => "fetcher", "name" => n.to_s } }
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

    def verb_published(argv)
      parse_format!(argv)
      emit({ "protocol" => Textus::PROTOCOL, "published" => store.published })
    end

    def emit(obj)
      @stdout.puts(JSON.generate(obj))
      0
    end

    def emit_error(err)
      @stdout.puts(JSON.generate(err.to_envelope))
      err.exit_code
    end

    def print_help
      @stdout.puts <<~HELP
        textus #{VERSION} — reference implementation of #{PROTOCOL}

        Usage:
          textus list [--prefix=KEY] --format=json
          textus where KEY --format=json
          textus get KEY --format=json
          textus put KEY --stdin --format=json
          textus schema KEY --format=json
          textus stale [--prefix=KEY] --format=json
      HELP
    end
  end
end
