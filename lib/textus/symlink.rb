require "json"
require "digest"
require "fileutils"

module Textus
  module Symlink
    def self.publish(source:, target:)
      FileUtils.mkdir_p(File.dirname(target))
      if File.exist?(target) || File.symlink?(target)
        if File.exist?(target) && !File.symlink?(target) && !managed?(target)
          raise PublishError.new("refusing to clobber non-symlink at #{target}")
        end

        File.delete(target)
        sentinel = target + ".textus-managed.json"
        FileUtils.rm_f(sentinel)
      end
      begin
        File.symlink(source, target)
      rescue NotImplementedError, Errno::EPERM
        FileUtils.cp(source, target)
        File.write(target + ".textus-managed.json", JSON.generate(
                                                      "source" => source,
                                                      "sha256" => Digest::SHA256.hexdigest(File.binread(source)),
                                                      "mode" => "copy",
                                                    ))
      end
    end

    def self.managed?(target)
      File.exist?(target + ".textus-managed.json")
    end
  end
end
