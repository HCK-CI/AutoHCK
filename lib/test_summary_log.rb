# frozen_string_literal: true

module AutoHCK
  # Shared per-test summary artifact (logs.txt) for test engines.
  # Engines map their own result objects into plain entry hashes; this class
  # only formats lines and writes/uploads the file.
  class TestSummaryLog
    SUMMARY_LOG_FILE = 'logs.txt'

    # entry keys: :status (required), :name (required), :runtime (optional),
    # :extra (optional suffix after [runtime], e.g. times or minidump marker)
    def self.format_line(status:, name:, runtime: nil, extra: nil)
      line = "#{status}: #{name}"
      line += " [#{runtime}]" unless runtime.nil? || runtime.to_s.empty?
      line += extra.to_s
      "#{line}\n"
    end

    def self.format_lines(entries)
      entries.map do |entry|
        format_line(
          status: entry.fetch(:status),
          name: entry.fetch(:name),
          runtime: entry[:runtime],
          extra: entry[:extra]
        )
      end.join
    end

    def self.write(project, content, logger: nil)
      logger&.info('Tests results logs updated via the result uploader')
      project.result_uploader&.update_file_content(content, SUMMARY_LOG_FILE)
      File.write("#{project.workspace_path}/#{SUMMARY_LOG_FILE}", content)
    end
  end
end
