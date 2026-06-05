# frozen_string_literal: true

module ClaudeMemory
  module Commands
    # Registry for CLI command lookup and dispatch
    # Maps command names to command classes and short descriptions.
    # Descriptions are authoritative for shell completion and help output;
    # keep them current when adding commands.
    class Registry
      # Map of command names to {class:, description:} entries.
      # As more commands are extracted, add them here.
      COMMANDS = {
        "help" => {class: HelpCommand, description: "Show help message"},
        "version" => {class: VersionCommand, description: "Show version"},
        "doctor" => {class: DoctorCommand, description: "Check system health"},
        "stats" => {class: StatsCommand, description: "Show statistics"},
        "promote" => {class: PromoteCommand, description: "Promote fact to global"},
        "search" => {class: SearchCommand, description: "Search indexed content"},
        "explain" => {class: ExplainCommand, description: "Explain a fact with receipts"},
        "conflicts" => {class: ConflictsCommand, description: "Show open conflicts"},
        "changes" => {class: ChangesCommand, description: "Show recent fact changes"},
        "recall" => {class: RecallCommand, description: "Recall facts matching query"},
        "sweep" => {class: SweepCommand, description: "Run maintenance"},
        "ingest" => {class: IngestCommand, description: "Ingest transcript delta"},
        "publish" => {class: PublishCommand, description: "Publish snapshot"},
        "db:init" => {class: DbInitCommand, description: "Initialize database"},
        "init" => {class: InitCommand, description: "Initialize ClaudeMemory"},
        "uninstall" => {class: UninstallCommand, description: "Remove configuration"},
        "serve-mcp" => {class: ServeMcpCommand, description: "Start MCP server"},
        "hook" => {class: HookCommand, description: "Run hook entrypoints"},
        "index" => {class: IndexCommand, description: "Index content"},
        "recover" => {class: RecoverCommand, description: "Recover database"},
        "compact" => {class: CompactCommand, description: "Compact databases"},
        "export" => {class: ExportCommand, description: "Export facts to JSON"},
        "git-lfs" => {class: GitLfsCommand, description: "Git LFS integration"},
        "install-skill" => {class: InstallSkillCommand, description: "Install agent skills"},
        "completion" => {class: CompletionCommand, description: "Generate shell completions"},
        "embeddings" => {class: EmbeddingsCommand, description: "Inspect embedding backend"},
        "reject" => {class: RejectCommand, description: "Mark a fact as rejected"},
        "restore" => {class: RestoreCommand, description: "Restore superseded facts from obsolete single-value classification"},
        "dedupe-conflicts" => {class: DedupeConflictsCommand, description: "Deduplicate historical open conflict rows that describe the same pair"},
        "reclassify-references" => {class: ReclassifyReferencesCommand, description: "Retag existing convention facts that match reference-material heuristics"},
        "census" => {class: CensusCommand, description: "Aggregate predicate usage across project databases"},
        "dashboard" => {class: DashboardCommand, description: "Open debugging dashboard"},
        "digest" => {class: DigestCommand, description: "Render a weekly markdown digest of memory activity"},
        "show" => {class: ShowCommand, description: "Print what memory would inject at the next SessionStart"},
        "otel" => {class: OtelCommand, description: "Configure or inspect OpenTelemetry ingestion from Claude Code"},
        "setup-vectors" => {class: SetupVectorsCommand, description: "Opt into vector recall — write provider env to .claude/settings.json + re-index"},
        "import-auto-memory" => {class: ImportAutoMemoryCommand, description: "Import Claude Code auto-memory .md files into project DB as facts"},
        "audit" => {class: AuditCommand, description: "Run memory health audit; report inconsistencies and optimizations"}
      }.freeze

      # Find a command class by name
      # @param command_name [String] the command name (e.g., "help", "version")
      # @return [Class, nil] the command class, or nil if not found
      def self.find(command_name)
        COMMANDS.dig(command_name, :class)
      end

      # Get all registered command names
      # @return [Array<String>] list of command names
      def self.all_commands
        COMMANDS.keys
      end

      # Check if a command is registered
      # @param command_name [String] the command name
      # @return [Boolean] true if registered
      def self.registered?(command_name)
        COMMANDS.key?(command_name)
      end

      # Get the short description for a command
      # @param command_name [String] the command name
      # @return [String, nil] the description, or nil if not registered
      def self.description(command_name)
        COMMANDS.dig(command_name, :description)
      end

      # Get all command descriptions as a hash
      # @return [Hash{String => String}] command name → description
      def self.descriptions
        COMMANDS.transform_values { |entry| entry[:description] }
      end
    end
  end
end
