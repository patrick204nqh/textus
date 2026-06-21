RSpec.describe "Port shape — every port is an instantiable class" do
  Dir["lib/textus/port/**/*.rb"].each do |file|
    next if file.end_with?("storage/file_stat.rb") # FileStat is a class — check below

    relative = file.delete_prefix("lib/textus/")
    # Map file path to constant name heuristically
    segments = relative.sub(%r{\.rb\z}, "").split("/")
    const_name = "Textus::#{segments.map { |s| s.split("_").map(&:capitalize).join }.join("::")}"

    klass = const_name.split("::").reduce(Object) { |mod, name| mod.const_get(name) }

    it "#{relative} defines a Class" do
      expect(klass).to be_a(Class), "#{const_name} is a #{klass.class}, not a Class"
    end
  end
end
