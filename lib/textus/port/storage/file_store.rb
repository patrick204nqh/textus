require "fileutils"

module Textus
  module Port
    module Storage
      # Pure filesystem I/O port. Wraps File/FileUtils/Etag with no knowledge
      # of envelopes, entries, schemas, or audit.
      class FileStore
        include Interface
        def read(path) = File.binread(path)

        def write(path, bytes)
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite(path, bytes)
        end

        # Raises Errno::ENOENT if absent — mirrors File.delete and matches the
        # semantics used by Store::Writer (which guards with File.exist? first).
        def delete(path) = File.delete(path)

        def exists?(path) = File.exist?(path)

        def etag(path) = Value::Etag.for_file(path)

        # Convenience filesystem ops so callers can go through the port
        # instead of calling FileUtils/Dir directly. Keeps filesystem
        # semantics in one place for easier testing and replacement.
        def mkdir_p(path)
          FileUtils.mkdir_p(path)
        end

        def mv(from_path, to_path)
          FileUtils.mkdir_p(File.dirname(to_path))
          FileUtils.mv(from_path, to_path)
        end

        def rmdir(path)
          Dir.rmdir(path)
        end

        def dir_empty?(dir)
          # Dir.empty? exists on modern Rubies; wrap for clarity
          Dir.empty?(dir)
        end
      end
    end
  end
end
