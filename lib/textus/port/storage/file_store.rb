require "fileutils"

module Textus
  module Port
    module Storage
      # Pure filesystem I/O port. Wraps File/FileUtils/Etag with no knowledge
      # of envelopes, entries, schemas, or audit.
      class FileStore
        def read(path) = File.binread(path)

        def write(path, bytes)
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite(path, bytes)
        end

        # Raises Errno::ENOENT if absent — mirrors File.delete and matches the
        # semantics used by Store::Writer (which guards with File.exist? first).
        def delete(path) = File.delete(path)

        def exists?(path) = File.exist?(path)

        def etag(path) = Etag.for_file(path)
      end
    end
  end
end
