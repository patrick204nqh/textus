# Replaces Doctor::Check::IllegalKeys. Validates nested entry file/directory
# names produce legal key segments.

# rubocop:disable Metrics/BlockLength
Textus.workflow "doctor-illegal-keys" do
  match "artifacts.doctor.illegal-keys"

  step :scan do |_, ctx|
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
        next if entry.ignored?(rel)

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

    { "content" => { "ok" => issues.empty?, "issues" => issues, "count" => issues.size } }
  end

  publish
end
# rubocop:enable Metrics/BlockLength
