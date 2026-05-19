require "json"
require "optparse"

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

    def run(argv)
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
      when "--version", "-v" then @stdout.puts(VERSION); 0
      when "--help", "-h"    then print_help; 0
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
      OptionParser.new do |o|
        o.on("--prefix=KEY") { |v| prefix = v }
        o.on("--zone=Z") { |v| zone = v }
        o.on("--format=FMT") {}
      end.permute!(argv)
      [prefix, zone]
    end

    def verb_list(argv)
      prefix, zone = parse_prefix_and_zone!(argv.dup)
      parse_format!(argv)
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
      prefix, zone = parse_prefix_and_zone!(argv.dup)
      parse_format!(argv)
      emit(store.stale(prefix: prefix, zone: zone))
    end

    def verb_put(argv)
      key = argv.shift or raise UsageError.new("put requires a key")
      as_flag = nil
      use_stdin = false
      OptionParser.new do |o|
        o.on("--stdin") { use_stdin = true }
        o.on("--as=ROLE") { |v| as_flag = v }
        o.on("--format=FMT") {}
      end.permute!(argv)
      raise UsageError.new("put requires --stdin in v1") unless use_stdin
      role = Role.resolve(flag: as_flag, env: ENV, root: store.root)

      payload = JSON.parse(@stdin.read)
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
