module Textus
  module Doctor
    class Check
      class IllegalKeys < Check
        def call
          out = []
          manifest.data.entries.each do |entry|
            next unless entry.nested?
            next if entry.publish_mode.keyless? # publish_tree files are opaque payload, never keys (ADR 0047)

            base = File.join(root, "data", entry.path)
            next unless File.directory?(base)

            check_all_paths(entry, base, out)
          end
          out
        end

        private

        def check_all_paths(entry, base, out)
          walk_nested(base) do |abs_path, is_dir|
            rel = abs_path.sub(%r{\A#{Regexp.escape(base)}/?}, "")
            next if entry.ignored?(rel)

            basename = File.basename(abs_path)
            stem = is_dir ? basename : basename.sub(/#{Regexp.escape(File.extname(basename))}\z/, "")
            next if stem.match?(Key::Grammar::SEGMENT)

            out << issue(abs_path, stem)
          end
        end

        def issue(abs_path, stem)
          {
            "code" => "key.illegal",
            "level" => "error",
            "subject" => abs_path,
            "path" => abs_path,
            "message" => "illegal key segment '#{stem}' at #{abs_path}",
            "fix" => "rename the file/directory so each segment matches [a-z0-9][a-z0-9-]* " \
                     "(lowercase, digits, hyphens)",
          }
        end

        def walk_nested(root, &block)
          Dir.each_child(root) do |name|
            abs = File.join(root, name)
            if File.directory?(abs)
              walk_nested(abs, &block)
              yield abs, true
            else
              yield abs, false
            end
          end
        end
      end
    end
  end
end
