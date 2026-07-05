require "fileutils"

module Textus
  module Infra
    class FileSystem
      module Interface
        def read(path) = raise NotImplementedError
        def write(path, bytes) = raise NotImplementedError
        def delete(path) = raise NotImplementedError
        def exists?(path) = raise NotImplementedError
        def mkdir_p(path) = raise NotImplementedError
        def mv(from, to) = raise NotImplementedError
        def copy(source, target) = raise NotImplementedError
        def glob(pattern) = raise NotImplementedError
        def etag(path) = raise NotImplementedError
      end

      include Interface

      def read(path) = File.binread(path)

      def write(path, bytes)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, bytes)
      end

      def delete(path) = File.delete(path)
      def exists?(path) = File.exist?(path)
      def size(path) = File.size(path)
      def mkdir_p(path) = FileUtils.mkdir_p(path)
      def rmdir(path) = Dir.rmdir(path)
      def dir_empty?(dir) = Dir.empty?(dir)
      def glob(pattern) = Dir.glob(pattern)
      def mv(from, to) = File.rename(from, to)
      def copy(source, target) = FileUtils.cp(source, target)
      def symlink?(path) = File.symlink?(path)
      def identical?(left, right) = FileUtils.identical?(left, right)
      def mtime(path) = File.mtime(path)
      def directory?(path) = File.directory?(path)

      def etag(path)
        Value::Etag.for_file(path)
      end

      def flock_exclusive(path, nonblock: false)
        File.open(path, File::RDWR | File::CREAT, 0o644) do |f|
          f.close_on_exec = true
          f.flock(nonblock ? File::LOCK_EX | File::LOCK_NB : File::LOCK_EX)
          yield f
        end
      end
    end
  end
end
