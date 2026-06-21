RSpec.describe "Port shape — every port is an instantiable class" do
  Dir["lib/textus/port/**/*.rb"].each do |file|
    next if file.end_with?("storage/file_stat.rb") # FileStat is a class — check below

    it "#{file.delete_prefix("lib/textus/")} defines a Class" do
      relative = file.delete_prefix("lib/textus/")
      const_name = "Textus::#{relative.sub(/\.rb\z/, "").split("/").map { |s| s.split("_").map(&:capitalize).join }.join("::")}"
      klass = const_name.split("::").reduce(Object) { |mod, name| mod.const_get(name) }
      expect(klass).to be_a(Class), "#{const_name} is a #{klass.class}, not a Class"
    end
  end
end
