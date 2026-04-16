# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Generates shell completion scripts for bash and zsh.
    # Outputs completion script to stdout for eval or redirection.
    class CompletionCommand < BaseCommand
      def call(args)
        opts = parse_options(args, {shell: detect_shell}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory completion [options]"
            parser.on("--shell SHELL", %w[bash zsh], "Shell type: bash or zsh (auto-detected)") { |v| o[:shell] = v }
          end
        end
        return 1 if opts.nil?

        case opts[:shell]
        when "zsh"
          stdout.puts zsh_completion
        when "bash"
          stdout.puts bash_completion
        else
          return failure("Unknown shell: #{opts[:shell]}. Use --shell bash or --shell zsh")
        end
        0
      end

      private

      def detect_shell
        shell = ENV.fetch("SHELL", "/bin/bash")
        File.basename(shell)
      end

      def command_names
        Registry.all_commands.sort
      end

      def zsh_completion
        commands_with_desc = Registry.descriptions.sort.map { |name, desc|
          "    '#{name}:#{desc}'"
        }.join("\n")

        <<~ZSH
          #compdef claude-memory

          _claude_memory() {
            local -a commands
            commands=(
          #{commands_with_desc}
            )

            _arguments -C \\
              '1:command:->command' \\
              '*::arg:->args'

            case $state in
              command)
                _describe 'command' commands
                ;;
              args)
                case $words[1] in
                  recall|search|explain)
                    _arguments '*:query:'
                    ;;
                  promote)
                    _arguments '*:fact_id:'
                    ;;
                  hook)
                    local -a subcommands
                    subcommands=('ingest:Ingest transcript' 'sweep:Run maintenance' 'publish:Publish snapshot' 'context:Inject context')
                    _describe 'subcommand' subcommands
                    ;;
                  compact|export|changes|stats|sweep|conflicts)
                    _arguments '--scope[Scope]:scope:(all global project)'
                    ;;
                  index)
                    _arguments '--vec[Build vector index]' '--rebuild[Rebuild from scratch]'
                    ;;
                  completion)
                    _arguments '--shell[Shell type]:shell:(bash zsh)'
                    ;;
                  dashboard)
                    _arguments '--port[Server port]:port:' '--no-open[Skip browser open]'
                    ;;
                  install-skill)
                    local -a skills
                    skills=(#{skill_names.map { |s| "'#{s}'" }.join(" ")})
                    _arguments '--list[List available skills]' '--force[Overwrite existing]' '1:skill:($skills)'
                    ;;
                esac
                ;;
            esac
          }

          _claude_memory "$@"
        ZSH
      end

      def bash_completion
        <<~BASH
          # bash completion for claude-memory

          _claude_memory() {
            local cur prev commands
            COMPREPLY=()
            cur="${COMP_WORDS[COMP_CWORD]}"
            prev="${COMP_WORDS[COMP_CWORD-1]}"
            commands="#{command_names.join(" ")}"

            if [[ ${COMP_CWORD} -eq 1 ]]; then
              COMPREPLY=( $(compgen -W "${commands}" -- "${cur}") )
              return 0
            fi

            case "${COMP_WORDS[1]}" in
              hook)
                COMPREPLY=( $(compgen -W "ingest sweep publish context" -- "${cur}") )
                ;;
              compact|export|changes|stats|sweep|conflicts)
                if [[ "${prev}" == "--scope" ]]; then
                  COMPREPLY=( $(compgen -W "all global project" -- "${cur}") )
                else
                  COMPREPLY=( $(compgen -W "--scope" -- "${cur}") )
                fi
                ;;
              install-skill)
                if [[ "${prev}" == "install-skill" ]]; then
                  COMPREPLY=( $(compgen -W "#{skill_names.join(" ")} --list --force" -- "${cur}") )
                fi
                ;;
              completion)
                if [[ "${prev}" == "--shell" ]]; then
                  COMPREPLY=( $(compgen -W "bash zsh" -- "${cur}") )
                else
                  COMPREPLY=( $(compgen -W "--shell" -- "${cur}") )
                fi
                ;;
            esac
            return 0
          }

          complete -F _claude_memory claude-memory
        BASH
      end

      def skill_names
        InstallSkillCommand::AVAILABLE_SKILLS.keys
      end
    end
  end
end
