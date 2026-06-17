# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Installs embedded skill files (agent definitions) to ~/.claude/commands/
    # for use as Claude Code slash commands.
    class InstallSkillCommand < BaseCommand
      SKILLS_DIR = File.expand_path("../skills", __FILE__)

      AVAILABLE_SKILLS = {
        "memory-recall" => {
          file: "memory-recall.md",
          description: "Memory recall agent — chains recall → explain → fact_graph"
        },
        "distill-transcripts" => {
          file: "distill-transcripts.md",
          description: "Distill transcripts — extract facts/entities/decisions from undistilled content"
        },
        "reflect" => {
          file: "reflect.md",
          description: "Reflect on observations — consolidate the episodic log and promote corroborated observations to facts"
        }
      }.freeze

      def call(args)
        opts = parse_options(args, {list: false, force: false}) do |o|
          OptionParser.new do |parser|
            parser.banner = "Usage: claude-memory install-skill [SKILL_NAME] [options]"
            parser.on("--list", "List available skills") { o[:list] = true }
            parser.on("--force", "Overwrite existing files") { o[:force] = true }
          end
        end
        return 1 if opts.nil?

        if opts[:list] || args.empty?
          return list_skills
        end

        skill_name = args.first
        install_skill(skill_name, force: opts[:force])
      end

      private

      def list_skills
        stdout.puts "Available skills:"
        AVAILABLE_SKILLS.each do |name, info|
          stdout.puts "  #{name} — #{info[:description]}"
        end
        stdout.puts ""
        stdout.puts "Install with: claude-memory install-skill <name>"
        0
      end

      def install_skill(name, force: false)
        skill = AVAILABLE_SKILLS[name]
        unless skill
          return failure("Unknown skill: #{name}. Run --list to see available skills.")
        end

        source = File.join(SKILLS_DIR, skill[:file])
        unless File.exist?(source)
          return failure("Skill file not found: #{source}")
        end

        target_dir = File.join(Dir.home, ".claude", "commands")
        FileUtils.mkdir_p(target_dir)

        target = File.join(target_dir, skill[:file])

        if File.exist?(target) && !force
          return failure("#{target} already exists. Use --force to overwrite.")
        end

        FileUtils.cp(source, target)
        stdout.puts "Installed #{name} to #{target}"
        stdout.puts "Use as: /#{File.basename(name, ".md")} <query>"
        0
      end
    end
  end
end
