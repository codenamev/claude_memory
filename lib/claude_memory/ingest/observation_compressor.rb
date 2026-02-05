# frozen_string_literal: true

require "json"

module ClaudeMemory
  module Ingest
    # Compresses tool call observations into human-readable summaries.
    # Reduces ~70% token usage vs raw tool I/O in provenance descriptions.
    #
    # @example
    #   compressor = ObservationCompressor.new
    #   summary = compressor.compress("Edit", '{"file_path":"/src/auth.rb","old_string":"def login","new_string":"def async_login"}')
    #   # => "Edited auth.rb: 'def login' → 'def async_login'"
    class ObservationCompressor
      MAX_SUMMARY_LENGTH = 200

      def compress(tool_name, tool_input_json)
        return nil if tool_input_json.nil? || tool_input_json.empty?

        input = parse_input(tool_input_json)
        return nil unless input

        summary = case tool_name
        when "Edit"
          compress_edit(input)
        when "Write"
          compress_write(input)
        when "Bash"
          compress_bash(input)
        when "Read"
          compress_read(input)
        when "Glob"
          compress_glob(input)
        when "Grep"
          compress_grep(input)
        when "Task"
          compress_task(input)
        when "WebFetch"
          compress_web_fetch(input)
        when "WebSearch"
          compress_web_search(input)
        when "NotebookEdit"
          compress_notebook_edit(input)
        else
          compress_generic(tool_name, input)
        end

        truncate(summary)
      end

      private

      def parse_input(json_str)
        JSON.parse(json_str)
      rescue JSON::ParserError
        nil
      end

      def compress_edit(input)
        file = short_path(input["file_path"])
        old_str = truncate_str(input["old_string"], 40)
        new_str = truncate_str(input["new_string"], 40)

        if old_str && new_str
          "Edited #{file}: '#{old_str}' → '#{new_str}'"
        elsif file
          "Edited #{file}"
        end
      end

      def compress_write(input)
        file = short_path(input["file_path"])
        content = input["content"]
        size = content ? content.length : 0

        "Created #{file} (#{size} chars)"
      end

      def compress_bash(input)
        command = input["command"]
        return "Ran shell command" unless command

        desc = input["description"]
        cmd = truncate_str(command, 80)

        if desc
          "Ran: #{desc}"
        else
          "Ran: #{cmd}"
        end
      end

      def compress_read(input)
        file = short_path(input["file_path"])
        offset = input["offset"]
        limit = input["limit"]

        parts = ["Read #{file}"]
        parts << "lines #{offset}-#{offset + limit}" if offset && limit
        parts.join(" ")
      end

      def compress_glob(input)
        pattern = input["pattern"]
        path = input["path"]

        if path
          "Glob #{pattern} in #{short_path(path)}"
        else
          "Glob #{pattern}"
        end
      end

      def compress_grep(input)
        pattern = input["pattern"]
        path = input["path"]

        if path
          "Searched '#{truncate_str(pattern, 40)}' in #{short_path(path)}"
        else
          "Searched '#{truncate_str(pattern, 40)}'"
        end
      end

      def compress_task(input)
        desc = input["description"]
        agent_type = input["subagent_type"]

        if desc
          "Spawned #{agent_type || "agent"}: #{truncate_str(desc, 60)}"
        else
          "Spawned #{agent_type || "agent"}"
        end
      end

      def compress_web_fetch(input)
        url = input["url"]
        "Fetched #{truncate_str(url, 60)}"
      end

      def compress_web_search(input)
        query = input["query"]
        "Searched web: '#{truncate_str(query, 60)}'"
      end

      def compress_notebook_edit(input)
        path = short_path(input["notebook_path"])
        mode = input["edit_mode"] || "replace"
        "Notebook #{mode} in #{path}"
      end

      def compress_generic(tool_name, input)
        keys = input.keys.first(3).join(", ")
        "#{tool_name}(#{keys})"
      end

      def short_path(path)
        return "unknown" unless path

        File.basename(path)
      end

      def truncate_str(str, max_len)
        return nil unless str

        str = str.gsub(/\s+/, " ").strip
        (str.length > max_len) ? str[0...max_len] + "..." : str
      end

      def truncate(summary)
        return nil unless summary

        (summary.length > MAX_SUMMARY_LENGTH) ? summary[0...MAX_SUMMARY_LENGTH] + "..." : summary
      end
    end
  end
end
