# frozen_string_literal: true

module AutoHCK
  # Shared per-test summary artifact (logs.txt) for test engines.
  # Engines map their own result objects into plain entry hashes; this class
  # only formats lines and writes/uploads the file.
  class TestSummaryLog
    SUMMARY_LOG_FILE = 'logs.txt'

    # entry keys: :status (required), :name (required),
    # :runtime (optional, actual executed time),
    # :estimationtime (optional, HLK estimate or functest timeout),
    # :minidump (optional, shared marker when a dump was collected),
    # :started_at / :finished_at (optional, shared across engines),
    # :extra (optional suffix, e.g. HLK queued time)
    #
    # Main bracket = estimationtime only (no fallback to runtime).
    # Actual runtime is appended as [runtime: ...] when set (after finish).
    # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/ParameterLists,Metrics/PerceivedComplexity
    def self.format_line(status:, name:, runtime: nil, estimationtime: nil,
                         minidump: false, started_at: nil, finished_at: nil, extra: nil)
      line = "#{status}: #{name}"
      line += " [#{estimationtime}]" unless estimationtime.nil? || estimationtime.to_s.empty?
      line += " [runtime: #{runtime}]" unless runtime.nil? || runtime.to_s.empty?
      line += '(with Minidump)' if minidump
      line += extra.to_s
      line += " [Started time: #{started_at}]" unless started_at.nil? || started_at.to_s.empty?
      line += " [Finished time: #{finished_at}]" unless finished_at.nil? || finished_at.to_s.empty?
      "#{line}\n"
    end
    # rubocop:enable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/ParameterLists,Metrics/PerceivedComplexity

    def self.format_lines(entries)
      entries.map do |entry|
        format_line(
          status: entry.fetch(:status),
          name: entry.fetch(:name),
          runtime: entry[:runtime],
          estimationtime: entry[:estimationtime],
          minidump: entry[:minidump],
          started_at: entry[:started_at],
          finished_at: entry[:finished_at],
          extra: entry[:extra]
        )
      end.join
    end

    def self.write(project, entries)
      content = format_lines(entries)
      File.write(File.join(project.workspace_path, SUMMARY_LOG_FILE), content)
      project.result_uploader&.update_file_content(content, SUMMARY_LOG_FILE)
      project.logger.info('Tests results logs updated')
    end
  end
end
