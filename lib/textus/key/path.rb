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
        primary_ext = Entry.for_format(mentry.format).extensions.first
        if File.extname(mentry.path) == ""
          File.join(data.root, "data", mentry.path + primary_ext)
        else
          File.join(data.root, "data", mentry.path)
        end
      end
    end
  end
end
