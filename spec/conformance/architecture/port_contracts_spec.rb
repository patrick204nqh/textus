# rubocop:disable RSpec/LeakyConstantDeclaration, RSpec/ContextWording, Lint/ConstantDefinitionInBlock
RSpec.describe "Port contract conformance" do
  PORT_INTERFACES = {
    Textus::Port::Storage::Interface => [Textus::Port::Storage::FileStore],
    Textus::Port::AuditLog::Interface => [Textus::Port::AuditLog],
    Textus::Port::Publisher::Interface => [Textus::Port::Publisher],
    Textus::Port::Clock::Interface => [Textus::Port::Clock],
    Textus::Port::BuildLock::Interface => [Textus::Port::BuildLock],
  }.freeze

  PORT_INTERFACES.each do |interface_mod, implementations|
    implementations.each do |impl_class|
      context "#{impl_class} implements #{interface_mod}" do
        interface_mod.instance_methods(false).each do |method_name|
          it "responds to ##{method_name}" do
            expect(build_instance(impl_class)).to respond_to(method_name)
          end
        end
      end
    end
  end

  def build_instance(klass)
    case klass.name
    when /FileStore/ then klass.new
    when /AuditLog/ then klass.new(Dir.tmpdir)
    when /Publisher/ then klass.new
    when /Clock/ then klass.new
    when /BuildLock/ then klass.new(root: Dir.tmpdir)
    else klass.new
    end
  end
end
# rubocop:enable RSpec/LeakyConstantDeclaration, RSpec/ContextWording, Lint/ConstantDefinitionInBlock
