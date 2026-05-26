module Textus
  # Run-once helper that renames files/directories whose basenames don't
  # conform to the strict key grammar (§3 of plan-1.2). Only walks
  # nested: true manifest entries — leaf entries with illegal declared
  # keys are caught by Manifest load and must be fixed by hand.
  module MigrateKeys
    SEGMENT = /\A[a-z0-9][a-z0-9-]*\z/

    module_function

    # Returns the envelope hash described in plan-1.2 §3.
    def run(store, write: false)
      plan = build_plan(store)
      collisions = plan[:collisions]
      renames = plan[:renames]

      ok = collisions.empty?
      apply!(store, renames) if write && ok

      {
        "protocol" => Textus::PROTOCOL,
        "mode" => write ? "write" : "dry-run",
        "renames" => renames.map { |r| envelope_rename(r) },
        "collisions" => collisions.map { |c| envelope_collision(c) },
        "ok" => ok,
      }
    end

    # ------------------------------------------------------------------
    # Plan construction
    # ------------------------------------------------------------------

    # Returns { renames: [...], collisions: [...] }
    # Each rename: { from:, to:, old_key:, new_key:, kind: :file|:dir }
    # Each collision: { target:, sources: [...] }
    def build_plan(store) # rubocop:disable Metrics/AbcSize
      renames = []
      target_buckets = Hash.new { |h, k| h[k] = [] } # target_path => [source_path, ...]

      store.manifest.entries.each do |entry|
        next unless entry.nested

        base = File.join(store.root, "zones", entry.path)
        next unless File.directory?(base)

        # Walk depth-first. Order matters when computing the "new key"
        # for files inside a renamed directory: we record renames bottom-up,
        # so children are renamed before their parents on apply.
        walk(base) do |abs_path, is_dir|
          next if abs_path == base

          basename = File.basename(abs_path)
          stem = is_dir ? basename : basename.sub(/#{Regexp.escape(File.extname(basename))}\z/, "")
          next if stem.match?(SEGMENT)

          new_stem = normalize(stem)
          # Skip if normalization yields the same stem (e.g. already-legal
          # under a different lens). In practice match?(SEGMENT) catches that
          # above; this is a safety net.
          next if new_stem == stem

          new_basename = is_dir ? new_stem : new_stem + File.extname(basename)
          target = File.join(File.dirname(abs_path), new_basename)
          target_buckets[target] << abs_path

          renames << {
            from: abs_path,
            to: target,
            kind: is_dir ? :dir : :file,
            entry: entry,
            base: base,
          }
        end
      end

      collisions = target_buckets.select { |_, srcs| srcs.length > 1 }
                                 .map { |t, srcs| { target: t, sources: srcs.sort } }

      # Drop colliding entries from renames (we won't apply any of them)
      colliding_targets = collisions.to_set { |c| c[:target] }
      renames.reject! { |r| colliding_targets.include?(r[:to]) }

      # Sort renames bottom-up (deepest path first) so children move before parents.
      renames.sort_by! { |r| -r[:from].count("/") }

      { renames: renames, collisions: collisions }
    end

    # Yields [absolute_path, is_dir] for every entry under root. Depth-first.
    def walk(root, &block)
      Dir.each_child(root) do |name|
        abs = File.join(root, name)
        if File.directory?(abs)
          walk(abs, &block)
          yield abs, true
        else
          yield abs, false
        end
      end
    end

    # Deterministic transform per plan §3.
    def normalize(s)
      s = s.downcase
      s = s.gsub(/[^a-z0-9-]/, "-") # ., _, and anything else become -
      s = s.gsub(/-+/, "-")
      s.sub(/\A-+/, "").sub(/-+\z/, "")
    end

    # ------------------------------------------------------------------
    # Apply
    # ------------------------------------------------------------------

    def apply!(store, renames)
      audit = Textus::Infra::AuditLog.new(store.root)
      renames.each do |r|
        # Bottom-up order means a child's ancestors haven't moved yet, so
        # `from`/`to` are valid as-recorded. The audit `key` reflects the
        # eventual full key once every rename in this batch has applied.
        from = r[:from]
        to = r[:to]
        File.rename(from, to)
        new_key = compute_new_key(r, renames)
        audit.append(
          role: "runner",
          verb: "migrate-keys",
          key: new_key,
          etag_before: nil,
          etag_after: nil,
          extras: { "from" => from, "to" => to },
        )
      end
    end

    # If an ancestor of `path` was renamed earlier in this batch, rewrite the path.
    def resolve_current_path(path, renames)
      out = path
      renames.each do |r|
        prefix = r[:from] + "/"
        out = r[:to] + out[r[:from].length..] if out.start_with?(prefix)
      end
      out
    end

    # New full key after applying all renames up through this one.
    def compute_new_key(rename, renames)
      base = rename[:base]
      entry = rename[:entry]
      new_to = resolve_current_path(rename[:to], renames)

      rel = new_to.sub(%r{\A#{Regexp.escape(base)}/?}, "")
      stripped = rel.sub(/#{Regexp.escape(File.extname(rel))}\z/, "") unless rename[:kind] == :dir
      stripped ||= rel
      segs = stripped.split("/").reject(&:empty?)
      (entry.key.split(".") + segs).join(".")
    end

    # ------------------------------------------------------------------
    # Envelope helpers
    # ------------------------------------------------------------------

    def envelope_rename(r)
      {
        "from" => r[:from],
        "to" => r[:to],
        "old_key" => path_to_key(r[:from], r[:base], r[:entry], r[:kind]),
        "new_key" => path_to_key(r[:to], r[:base], r[:entry], r[:kind]),
      }
    end

    def envelope_collision(col)
      { "target" => col[:target], "sources" => col[:sources] }
    end

    def path_to_key(path, base, entry, kind)
      rel = path.sub(%r{\A#{Regexp.escape(base)}/?}, "")
      stripped =
        if kind == :dir
          rel
        else
          rel.sub(/#{Regexp.escape(File.extname(rel))}\z/, "")
        end
      segs = stripped.split("/").reject(&:empty?)
      (entry.key.split(".") + segs).join(".")
    end
  end
end
