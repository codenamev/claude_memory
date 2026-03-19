# frozen_string_literal: true

module ClaudeMemory
  module MCP
    module Handlers
      # Context-aware query handlers (facts by tool, branch, directory)
      module ContextHandlers
        def facts_by_tool(args)
          tool_name = args["tool_name"]
          scope = extract_scope(args)
          limit = extract_limit(args, default: 20)

          results = @recall.facts_by_tool(tool_name, limit: limit, scope: scope)
          ResponseFormatter.format_tool_facts(tool_name, scope, results)
        end

        def facts_by_context(args)
          scope = extract_scope(args)
          limit = extract_limit(args, default: 20)

          if args["git_branch"]
            results = @recall.facts_by_branch(args["git_branch"], limit: limit, scope: scope)
            context_type = "git_branch"
            context_value = args["git_branch"]
          elsif args["cwd"]
            results = @recall.facts_by_directory(args["cwd"], limit: limit, scope: scope)
            context_type = "cwd"
            context_value = args["cwd"]
          else
            return {error: "Must provide either git_branch or cwd parameter"}
          end

          ResponseFormatter.format_context_facts(context_type, context_value, scope, results)
        end
      end
    end
  end
end
