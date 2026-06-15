module Textus
  module Key
    module Path
      # Returns the absolute filesystem path for a manifest entry (the leaf file,
      # not a nested directory). Adds the format's primary extension when the
      # manifest entry's `path:` is extensionless.
      #
      # The first argument is a Manifest::Data (or anything responding to .root);
      # callers historically passed the whole Manifest but should now pass
      # `manifest.data`.
      def self.resolve(data, mentry)
        primary_ext = Format.for(mentry.format).extensions.first
        rel_path = normalize_relative_path(mentry.path)
        if File.extname(mentry.path) == ""
          File.join(data.root, rel_path + primary_ext)
        else
          File.join(data.root, rel_path)
        end
      end

      def self.normalize_relative_path(path)
        return path if path.start_with?("data/")

        File.join("data", path)
      end
    end
  end
end
