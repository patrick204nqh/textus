require "spec_helper"

RSpec.describe Textus::Port::Storage::FileStat do
  subject(:stat) { described_class.new }

  let(:tmp) { Dir.mktmpdir("textus-file-stat") }

  after { FileUtils.remove_entry(tmp) if File.directory?(tmp) }

  describe "#exists?" do
    it "returns false for a missing path" do
      expect(stat.exists?(File.join(tmp, "absent.txt"))).to be(false)
    end

    it "returns true for an existing file" do
      path = File.join(tmp, "present.txt")
      File.write(path, "x")
      expect(stat.exists?(path)).to be(true)
    end
  end

  describe "#read" do
    it "returns binary contents of the file" do
      path = File.join(tmp, "data.bin")
      bytes = "hello \xFF\x00".b
      File.binwrite(path, bytes)
      expect(stat.read(path)).to eq(bytes)
      expect(stat.read(path).encoding).to eq(Encoding::ASCII_8BIT)
    end
  end

  describe "#mtime" do
    it "returns a Time instance" do
      path = File.join(tmp, "ts.txt")
      File.write(path, "x")
      expect(stat.mtime(path)).to be_a(Time)
    end

    it "agrees with File.mtime" do
      path = File.join(tmp, "ts2.txt")
      File.write(path, "x")
      expect(stat.mtime(path)).to eq(File.mtime(path))
    end
  end

  describe "#directory?" do
    it "returns true for a directory" do
      expect(stat.directory?(tmp)).to be(true)
    end

    it "returns false for a file" do
      path = File.join(tmp, "file.txt")
      File.write(path, "x")
      expect(stat.directory?(path)).to be(false)
    end

    it "returns false for a missing path" do
      expect(stat.directory?(File.join(tmp, "nope"))).to be(false)
    end
  end

  describe "#glob" do
    it "returns a sorted Array of matching paths" do
      %w[c.txt a.txt b.txt].each { |f| File.write(File.join(tmp, f), "") }
      results = stat.glob(File.join(tmp, "*.txt"))
      expect(results).to be_a(Array)
      expect(results).to eq(results.sort)
    end

    it "returns all matches" do
      %w[x.rb y.rb z.rb].each { |f| File.write(File.join(tmp, f), "") }
      results = stat.glob(File.join(tmp, "*.rb"))
      expect(results.map { |p| File.basename(p) }.sort).to eq(%w[x.rb y.rb z.rb])
    end

    it "returns an empty array when nothing matches" do
      expect(stat.glob(File.join(tmp, "*.no_match"))).to eq([])
    end
  end
end
