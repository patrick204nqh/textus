module Textus
  module Agent
    class Runner
      Result = ::Data.define(:exit_code, :stdout, :stderr)

      def exec(script_path, timeout: 30)
        output, err, status = Open3.capture3(script_path)
        Result.new(exit_code: status.exitstatus, stdout: output, stderr: err)
      rescue Errno::ENOENT
        Result.new(exit_code: -1, stdout: "", stderr: "script not found: #{script_path}")
      end

      def test(test_path, timeout: 30)
        exec(test_path, timeout:)
      end
    end
  end
end
