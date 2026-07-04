# Single workflow for all doctor checks — runs on knowledge changes,
# publishes health data to artifacts.doctor, then triggers boot.

Textus.workflow "doctor" do
  on "knowledge.loop.**"
  priority 20

  # ── Naming convention (was naming_check.rb, loop_shape.rb) ──────
  # Validates ALL manifest entries with naming: — single check covers
  # the old per-scope checks (loop-intent, loop-evidence, etc.) plus
  # any entry family added to the manifest.
  check "naming-convention" do |ctx|
    manifest = ctx.manifest
    issues = []
    manifest.data.entries.each do |entry|
      next unless entry.naming

      pattern = Textus::Protocol::V4::NAMING_PATTERNS.fetch(entry.naming)
      root = ctx.layout.root
      base = File.join(root, Textus::Protocol::Key::Path.normalize_relative_path(entry.path))
      next unless File.directory?(base)

      ext_glob = entry.format == "md" ? "*.md" : "*"
      Dir.glob(File.join(base, "**", ext_glob)).each do |path|
        filename = File.basename(path)
        next if pattern.match?(filename)

        rel = path.sub(%r{\A#{Regexp.escape(base)}/?}, "")
        stem = rel.sub(/#{Regexp.escape(File.extname(rel))}\z/, "")
        segs = stem.split("/").reject(&:empty?)
        key = ([entry.key] + segs).join(".")

        issues << {
          "code" => "loop.naming",
          "level" => "warning",
          "subject" => key,
          "message" => "#{filename} does not match the required naming pattern for #{entry.key} (#{entry.naming})",
          "fix" => "rename to match #{pattern.inspect}",
        }
      end
    end
    issues
  end

  # ── Manifest file integrity (was manifest_files.rb) ────────────
  check "manifest" do |ctx|
    manifest = ctx.manifest
    file_system = ctx.file_system
    layout = ctx.layout
    schemas = ctx.schemas
    issues = []

    manifest.data.entries.each do |entry|
      next if entry.nested? || entry.derived? || entry.external? || entry.respond_to?(:tracked?) && !entry.tracked?

      path = Textus::Protocol::Key::Path.resolve(manifest.data, entry)
      unless file_system.exists?(path)
        issues << { "code" => "manifest.missing_file", "severity" => "info",
                    "subject" => entry.key,
                    "message" => "declared entry has no file on disk at #{path}",
                    "fix" => "create the entry with 'textus put #{entry.key} --stdin --as=<role>'" }
      end

      entry.publish_to.each do |target|
        tmpl = target.respond_to?(:template) ? target.template : nil
        next unless tmpl

        to_path = target.respond_to?(:to) ? target.to : target.to_s
        tpath = layout.template_path(tmpl)
        next if File.exist?(tpath)

        issues << { "code" => "publish.missing_template", "severity" => "warning",
                    "subject" => entry.key,
                    "message" => "publish target '#{to_path}' references missing template '#{tmpl}'",
                    "fix" => "create the template at #{tpath}" }
      end

      next unless entry.schema
      next if schemas.fetch_or_nil(entry.schema)

      issues << { "code" => "manifest.missing_schema", "severity" => "warning",
                  "subject" => entry.key,
                  "message" => "entry '#{entry.key}' declares schema '#{entry.schema}' but no schema file found",
                  "fix" => "add the schema file to schemas/ directory" }
    end

    issues
  end

  # ── Publish tree overlap (was publish_tree_overlap.rb) ─────────
  check "publish-overlap" do |ctx|
    entries = ctx.manifest.data.entries
    trees = entries.select { |entry| entry.nested? && entry.publish_tree }
    derived_targets = entries.flat_map { |entry| Array(entry.publish_to).map { |rel| [entry, rel] } }
    issues = []

    trees.each do |tree|
      target_prefix = "#{tree.publish_tree.chomp("/")}/"

      derived_targets.each do |(derived, rel)|
        next unless rel.start_with?(target_prefix)

        rel_to_target = rel.delete_prefix(target_prefix)
        next if tree.ignored?(rel_to_target)

        basename = File.basename(rel_to_target)
        issues << {
          "code" => "publish.tree_index_overlap",
          "level" => "warning",
          "subject" => tree.key,
          "message" => "publish_tree '#{tree.publish_tree}' overlaps derived entry " \
                       "'#{derived.key}' publish_to '#{rel}'; the tree's prune will delete it on rebuild",
          "fix" => "add a glob covering '#{rel_to_target}' to entry '#{tree.key}' ignore " \
                   "(e.g. ignore: [\"**/#{basename}\"])",
        }
      end
    end

    issues
  end

  # ── Protocol version (was doctor_protocol_version.rb) ──────────
  check "protocol-version" do |ctx|
    issues = []
    path = ctx.layout.manifest_path

    if File.exist?(path)
      doc = YAML.safe_load_file(path, aliases: false) || {}
      version = doc["version"]
      if version != "textus/4"
        issues << {
          "code" => "protocol_mismatch",
          "level" => "error",
          "subject" => path,
          "message" => "Store reports version=#{version.inspect}; this gem expects textus/4.",
          "fix" => "Upgrade the store's manifest version to textus/4 (see CHANGELOG for breaking changes).",
        }
      end
    end

    issues
  end

  # ── Schema integrity (was doctor_schema_parse_error.rb + doctor_schema_violations.rb) ──
  check "schemas" do |ctx|
    dir = ctx.layout.schemas_dir
    manifest = ctx.manifest
    schemas = ctx.schemas
    issues = []

    if File.directory?(dir)
      Dir.glob(File.join(dir, "**", "*.yaml")).each do |path|
        schema = begin
          Textus::Protocol::Schema.load(path)
        rescue StandardError => e
          issues << {
            "code" => "schema.parse_error",
            "level" => "error",
            "subject" => path,
            "message" => "schema failed to parse: #{e.class}: #{e.message}",
            "fix" => "fix the YAML at #{path} (check indentation, quoted scalars, and aliases)",
          }
          next
        end

        unowned = schema.unowned_fields
        next if unowned.empty?

        issues << {
          "code" => "schema.unowned_fields",
          "level" => "info",
          "subject" => schema.name || File.basename(path, ".yaml"),
          "message" => "schema has fields without maintained_by: #{unowned.join(", ")}",
          "fix" => "add 'maintained_by: <role>' to each field in #{path} (optional but recommended)",
        }
      end
    end

    # Frontmatter conformance
    manifest.resolver.enumerate(include_keyless: true).each do |row|
      key = row[:key]
      envelope = ctx.read(key)
      next unless envelope

      schema_ref = envelope.schema_ref
      next unless schema_ref

      schema = schemas.fetch_or_nil(schema_ref)
      next unless schema

      frontmatter = envelope.meta&.dig("_meta") || envelope.meta || {}
      begin
        schema.validate!(frontmatter)
      rescue Textus::SchemaViolation => e
        issues << {
          "code" => "schema_violation",
          "level" => "error",
          "subject" => key,
          "message" => "#{schema_ref}: #{e.message}",
          "fix" => "update _meta to satisfy schema '#{schema_ref}'",
        }
      end
    end

    issues
  end

  # ── Illegal key segments (was doctor_illegal_keys.rb) ──────────
  check "key-naming" do |ctx|
    issues = []
    root = ctx.layout.root
    manifest = ctx.manifest

    walk_nested = lambda do |base, &block|
      Dir.each_child(base) do |name|
        abs = File.join(base, name)
        if File.directory?(abs)
          walk_nested.call(abs, &block)
          block.call(abs, true)
        else
          block.call(abs, false)
        end
      end
    end

    manifest.data.entries.each do |entry|
      next unless entry.nested?
      next if entry.publish_mode.keyless?

      base = File.join(root, Textus::Protocol::Key::Path.normalize_relative_path(entry.path))
      next unless File.directory?(base)

      walk_nested.call(base) do |abs_path, is_dir|
        rel = abs_path.sub(%r{\A#{Regexp.escape(base)}/?}, "")
        next if entry.respond_to?(:ignored?) && entry.ignored?(rel)

        basename = File.basename(abs_path)
        stem = is_dir ? basename : basename.sub(/#{Regexp.escape(File.extname(basename))}\z/, "")
        next if stem.match?(Textus::Protocol::Key::Grammar::SEGMENT)

        issues << {
          "code" => "key.illegal",
          "level" => "error",
          "subject" => abs_path,
          "path" => abs_path,
          "message" => "illegal key segment '#{stem}' at #{abs_path}",
          "fix" => "rename the file/directory so each segment matches [a-z0-9][a-z0-9-]* " \
                   "(lowercase, digits, hyphens)",
        }
      end
    end

    issues
  end

  # ── Proposal target validity (was doctor_proposal_targets.rb) ──
  check "proposal-targets" do |ctx|
    manifest = ctx.manifest
    queue = manifest.policy.queue_lane
    issues = []

    unless queue.nil?
      rows = ctx.manifest.resolver.enumerate.select { |r| r[:key].start_with?("#{queue}.") }

      rows.each do |row|
        key = row[:key]
        envelope = ctx.read(key)

        target = envelope&.meta&.dig("proposal", "target_key")
        next if target.nil?

        begin
          lane = manifest.resolver.resolve(target).entry.lane
          next if lane.to_s == "knowledge"

          issues << {
            "code" => "proposal.target_not_canon",
            "level" => "warning",
            "subject" => key,
            "message" => "proposal '#{key}' targets '#{target}' in zone '#{lane}' (not canon); it can never be accepted",
            "fix" => "delete the proposal, or repoint target_key at a canon zone",
          }
        rescue Textus::UnknownKey
          issues << {
            "code" => "proposal.target_unresolved",
            "level" => "warning",
            "subject" => key,
            "message" => "proposal '#{key}' targets '#{target}', which resolves to no declared entry",
            "fix" => "delete the proposal, or fix target_key",
          }
        end
      end
    end

    issues
  end

  # ── Generator drift (was doctor_generator_drift.rb) ────────────
  check "generator-drift" do |ctx|
    issues = []
    root = ctx.layout.root

    ctx.manifest.data.entries.each do |entry|
      next unless entry.derived? || entry.external?
      next unless entry.sources && !entry.sources.empty?

      entry_path = entry.path ? File.join(root, entry.path) : nil
      next unless entry_path && File.exist?(entry_path)

      entry_mtime = File.mtime(entry_path)

      entry.sources.each do |src|
        src_path = File.join(root, src)
        next unless File.exist?(src_path)

        next unless File.mtime(src_path) > entry_mtime

        issues << {
          "code" => "generator_drift",
          "level" => "warning",
          "subject" => entry.key,
          "message" => "source '#{src}' is newer than produced entry '#{entry.key}'",
          "fix" => "rematerialize the entry: `textus drain`",
        }
      end
    end

    issues
  end

  # ── Raw asset paths (was doctor_raw_asset_paths.rb) ────────────
  check "raw-assets" do |ctx|
    raw_lane = ctx.manifest.data.declared_lane_kinds.find { |_, k| k == :raw }&.first
    issues = []

    unless raw_lane.nil?
      ctx.manifest.resolver.enumerate.each do |row|
        next unless row[:key].start_with?("raw.")
        next unless row[:path] && File.exist?(row[:path])

        raw_content = begin
          YAML.safe_load_file(row[:path])
        rescue StandardError
          nil
        end
        next unless raw_content.is_a?(Hash)

        asset = raw_content["asset"]
        next unless asset.is_a?(String) && !asset.empty?

        asset_path = File.join(ctx.layout.root, "assets", asset)
        next if File.exist?(asset_path)

        issues << {
          "code" => "raw_asset.missing_file",
          "level" => "error",
          "subject" => row[:key],
          "message" => "raw entry '#{row[:key]}' references asset '#{asset}' which does not exist at #{asset_path}",
          "fix" => "re-ingest the asset: textus key-delete #{row[:key]}, then textus ingest",
        }
      end
    end

    issues
  end

  # ── Scratchpad source references (was doctor_scratchpad_sources.rb) ──
  check "scratchpad-sources" do |ctx|
    issues = []

    ctx.manifest.resolver.enumerate.each do |row|
      next unless row[:key].start_with?("scratchpad.notes.")
      next unless row[:path] && File.exist?(row[:path])

      content = begin
        File.read(row[:path])
      rescue StandardError
        nil
      end
      next if content.nil?

      match = content.match(/\A---\n(.*?)\n---/m)
      next if match.nil?

      front = begin
        YAML.safe_load(match[1])
      rescue StandardError
        nil
      end

      sources = Array(front&.dig("sources")).filter_map do |source|
        case source
        when String then source
        when Hash then source["key"]
        end
      end

      sources.each do |raw_key|
        exists = begin
          path = ctx.manifest.resolver.resolve(raw_key).path
          File.exist?(path)
        rescue Textus::UnknownKey, Textus::Error
          false
        end
        next if exists

        issues << {
          "code" => "scratchpad.source_missing",
          "level" => "warning",
          "subject" => row[:key],
          "message" => "scratchpad entry '#{row[:key]}' references raw key '#{raw_key}' which does not exist in the store",
          "fix" => "re-ingest the source: textus ingest ..., or remove the stale sources: entry",
        }
      end
    end

    issues
  end

  # ── Stale reviewed stamp (was doctor_stale_reviewed_stamp.rb) ──
  check "reviewed-stamp" do |ctx|
    stamp_re = /\*\*reviewed\*\*\s+\d{4}-\d{2}\s+\(v(\d+\.\d+(?:\.\d+)?)\)/
    threshold = 5
    current_minor = Textus::VERSION.sub(/\Av/, "").split(".").map(&:to_i)[1] || 0
    issues = []

    ctx.manifest.resolver.enumerate.each do |row|
      next unless row[:key].to_s.start_with?("knowledge.")
      next unless row[:path] && File.file?(row[:path])

      body = File.read(row[:path])
      match = body.match(stamp_re)
      next if match.nil?

      reviewed_minor = match[1].sub(/\Av/, "").split(".").map(&:to_i)[1] || 0
      behind = current_minor - reviewed_minor
      next unless behind > threshold

      current_short = Textus::VERSION[/\A\d+\.\d+/]
      issues << {
        "code" => "stale_reviewed_stamp",
        "level" => "warning",
        "subject" => row[:key].to_s,
        "message" => "reviewed at v#{match[1]}; current is v#{Textus::VERSION} " \
                     "(#{behind} minor versions behind, threshold is #{threshold})",
        "fix" => "review the doc and update the stamp to: **reviewed** YYYY-MM (v#{current_short})",
      }
    end

    issues
  end

  # ── Sentinel integrity (was doctor_sentinels.rb) ───────────────
  check "sentinels" do |ctx|
    dir = ctx.layout.sentinels_root
    issues = []

    if File.directory?(dir)
      Dir.glob(File.join(dir, "**", "*.sentinel.json")).each do |sentinel_path|
        sentinel = begin
          JSON.parse(File.read(sentinel_path))
        rescue StandardError
          nil
        end

        if sentinel.nil?
          issues << { "code" => "sentinel.parse_error", "level" => "warning", "subject" => sentinel_path,
                      "message" => "sentinel is not valid JSON",
                      "fix" => "delete and re-run 'textus drain' to regenerate" }
          next
        end

        target = sentinel["target"]
        next unless target && !File.exist?(target)

        issues << { "code" => "sentinel.orphan", "level" => "warning", "subject" => target,
                    "message" => "sentinel target #{target} no longer exists",
                    "fix" => "delete #{sentinel_path} or restore the target" }
      end
    end

    issues
  end

  # ── Audit log (was doctor_audit_log.rb) ────────────────────────
  check "audit-log" do |ctx|
    store = ctx.container.store
    issues = []
    latest = store.audit_log.latest

    if latest.nil?
      issues << { "code" => "audit.empty", "level" => "info", "subject" => "audit",
                  "message" => "audit log is empty", "fix" => nil }
    end

    issues
  end

  # ── Cursor retention (was doctor_cursor_retention.rb) ──────────
  check "cursors" do |ctx|
    store = ctx.container.store
    issues = []
    roles = ctx.manifest.data.role_caps.keys.map(&:to_s)

    roles.each do |role|
      cursor = store.cursor_store.get(role)[:seq]
      next if cursor.nil? || cursor <= 0

      min_seq = store.audit_log.min_available
      next unless min_seq && cursor < min_seq

      issues << { "code" => "cursor.expired", "level" => "warning",
                  "subject" => "cursor:#{role}",
                  "message" => "cursor for role '#{role}' (seq #{cursor}) is no longer available",
                  "fix" => "call pulse to get a fresh cursor" }
    end

    issues
  end

  save to: "artifacts.doctor"
  notify "artifacts.boot"
end
