# Feature Implementation Patterns

## Expert Review Applied

This guide demonstrates best practices from our Ruby experts:
- **Sandi Metz**: Small methods, dependency injection, SRP
- **Jeremy Evans**: DateTime columns, proper Sequel usage
- **Kent Beck**: Clear intent, testable design
- **Avdi Grimm**: Confident code, meaningful return values
- **Gary Bernhardt**: Boundaries, functional core/imperative shell

---

## Common Feature Types & Recipes

### Pattern 1: Adding a Database Table

**Use Case**: ROI metrics, tool usage tracking, logs

**Recipe:**
```ruby
# 1. Increment SCHEMA_VERSION in sqlite_store.rb
SCHEMA_VERSION = 7

# 2. Add migration method
def migrate_to_v7!
  @db.create_table?(:ingestion_metrics) do
    primary_key :id
    foreign_key :content_item_id, :content_items, null: false
    Integer :input_tokens, null: false, default: 0
    Integer :output_tokens, null: false, default: 0
    Integer :facts_extracted, null: false, default: 0
    DateTime :created_at, null: false  # ✅ Jeremy Evans: Use DateTime, not String
  end
end

# 3. Call in run_migrations!
def run_migrations!
  current = schema_version
  migrate_to_v7! if current < 7
  update_schema_version(SCHEMA_VERSION)
end

# 4. Add accessor method
def ingestion_metrics
  @db[:ingestion_metrics]
end

private

# ✅ Sandi Metz: Extract small, focused methods
def schema_version
  @db.fetch("PRAGMA user_version").first[:user_version]
end

def update_schema_version(version)
  @db.run("PRAGMA user_version = #{version}")
end
```

**Expert Notes:**
- ✅ **Jeremy Evans**: DateTime columns are more efficient than String timestamps
- ✅ **Sandi Metz**: Small helper methods for schema version management
- ✅ **Kent Beck**: Migration method name reveals intent

**Tests:**
```ruby
# spec/claude_memory/store/sqlite_store_spec.rb
RSpec.describe ClaudeMemory::Store::SQLiteStore do
  describe "schema version 7" do
    it "creates ingestion_metrics table" do
      expect(store.db.table_exists?(:ingestion_metrics)).to be true
    end

    it "uses DateTime for created_at column" do
      schema = store.db.schema(:ingestion_metrics)
      created_at_column = schema.find { |col| col[0] == :created_at }

      expect(created_at_column[1][:type]).to eq(:datetime)
    end

    it "includes all required columns" do
      columns = store.db.schema(:ingestion_metrics).map { |c| c[0] }
      expected = [:id, :content_item_id, :input_tokens, :output_tokens,
                  :facts_extracted, :created_at]

      expect(columns).to match_array(expected)
    end
  end
end
```

**Time Estimate**: 15-20 minutes

---

### Pattern 2: Adding a New CLI Command

**Use Case**: Stats enhancements, embed command, new utilities

**Recipe:**
```ruby
# 1. Create command file
# lib/claude_memory/commands/metrics_command.rb
module ClaudeMemory
  module Commands
    class MetricsCommand < BaseCommand
      # ✅ Gary Bernhardt: Inject dependencies, don't create them
      def initialize(stdout: $stdout, stderr: $stderr, store_manager: nil)
        super(stdout: stdout, stderr: stderr)
        @store_manager = store_manager
      end

      def call(args)
        opts = parse_options(args)
        return 1 if opts.nil?

        # ✅ Gary Bernhardt: Ensure cleanup even on exception
        manager = store_manager_for(opts)

        result = execute_command(manager, opts)
        output_result(result, opts)

        0
      ensure
        manager&.close
      end

      private

      # ✅ Sandi Metz: Small, focused methods
      def parse_options(args)
        opts = default_options

        OptionParser.new do |parser|
          parser.banner = "Usage: claude-memory metrics [options]"
          parser.on("--format FORMAT", ["text", "json"], "Output format") do |f|
            opts[:format] = f
          end
        end.parse!(args)

        opts
      rescue OptionParser::InvalidOption => e
        stderr.puts "Error: #{e.message}"
        nil
      end

      def default_options
        { format: "text" }
      end

      # ✅ Gary Bernhardt: Factory method for testability
      def store_manager_for(opts)
        @store_manager || Store::StoreManager.new
      end

      # ✅ Kent Beck: Method name reveals intent
      def execute_command(manager, opts)
        MetricsCalculator.new(manager.global_store).calculate
      end

      # ✅ Avdi Grimm: Tell, don't ask - formatter knows how to format
      def output_result(result, opts)
        formatter = formatter_for(opts[:format])
        stdout.puts formatter.format(result)
      end

      def formatter_for(format)
        case format
        when "json"
          JsonMetricsFormatter.new
        else
          TextMetricsFormatter.new
        end
      end
    end

    # ✅ Gary Bernhardt: Pure calculation logic, no I/O
    class MetricsCalculator
      def initialize(store)
        @store = store
      end

      def calculate
        {
          total_input_tokens: sum_column(:input_tokens),
          total_output_tokens: sum_column(:output_tokens),
          total_facts: sum_column(:facts_extracted),
          efficiency: calculate_efficiency
        }
      end

      private

      def sum_column(column)
        @store.ingestion_metrics.sum(column) || 0
      end

      def calculate_efficiency
        facts = sum_column(:facts_extracted)
        tokens = sum_column(:input_tokens)

        return 0.0 if tokens.zero?

        (facts.to_f / tokens * 1000).round(2)
      end
    end

    # ✅ Sandi Metz: Single responsibility - knows how to format
    class TextMetricsFormatter
      def format(metrics)
        [
          "Token Economics:",
          "  Input tokens:    #{metrics[:total_input_tokens]}",
          "  Output tokens:   #{metrics[:total_output_tokens]}",
          "  Facts extracted: #{metrics[:total_facts]}",
          "  Efficiency:      #{metrics[:efficiency]} facts/1k tokens"
        ].join("\n")
      end
    end

    class JsonMetricsFormatter
      def format(metrics)
        JSON.pretty_generate(metrics)
      end
    end
  end
end

# 2. Register in registry
# lib/claude_memory/commands/registry.rb
COMMANDS = {
  # ... existing
  "metrics" => MetricsCommand
}.freeze

# 3. Add to help text
# lib/claude_memory/commands/help_command.rb
"  metrics            Display token usage and efficiency metrics"
```

**Expert Notes:**
- ✅ **Gary Bernhardt**: Dependencies injected, pure calculator logic separated from I/O
- ✅ **Sandi Metz**: Small classes with single responsibility (calculator, formatters)
- ✅ **Kent Beck**: Clear method names that reveal intent
- ✅ **Avdi Grimm**: No nil checks needed, formatters handle their own formatting

**Tests:**
```ruby
# spec/claude_memory/commands/metrics_command_spec.rb
RSpec.describe ClaudeMemory::Commands::MetricsCommand do
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:store_manager) { instance_double(ClaudeMemory::Store::StoreManager) }
  let(:global_store) { instance_double(ClaudeMemory::Store::SQLiteStore) }
  let(:command) do
    described_class.new(
      stdout: stdout,
      stderr: stderr,
      store_manager: store_manager
    )
  end

  before do
    allow(store_manager).to receive(:global_store).and_return(global_store)
    allow(store_manager).to receive(:close)
  end

  describe "#call" do
    let(:metrics_dataset) { double("metrics_dataset") }

    before do
      allow(global_store).to receive(:ingestion_metrics).and_return(metrics_dataset)
      allow(metrics_dataset).to receive(:sum).with(:input_tokens).and_return(1000)
      allow(metrics_dataset).to receive(:sum).with(:output_tokens).and_return(500)
      allow(metrics_dataset).to receive(:sum).with(:facts_extracted).and_return(10)
    end

    it "returns success exit code" do
      expect(command.call([])).to eq(0)
    end

    it "closes store manager even on exception" do
      allow(global_store).to receive(:ingestion_metrics).and_raise("DB error")

      expect { command.call([]) }.to raise_error("DB error")
      expect(store_manager).to have_received(:close)
    end

    it "displays metrics in text format by default" do
      command.call([])
      output = stdout.string

      expect(output).to include("Token Economics:")
      expect(output).to include("Input tokens:    1000")
      expect(output).to include("Facts extracted: 10")
      expect(output).to include("Efficiency:      10.0 facts/1k tokens")
    end

    context "with --format json" do
      it "outputs JSON format" do
        command.call(["--format", "json"])

        output = JSON.parse(stdout.string)
        expect(output["total_input_tokens"]).to eq(1000)
        expect(output["efficiency"]).to eq(10.0)
      end
    end

    context "with invalid option" do
      it "returns error code" do
        expect(command.call(["--invalid"])).to eq(1)
        expect(stderr.string).to include("Error:")
      end
    end
  end
end

# spec/claude_memory/commands/metrics_calculator_spec.rb
RSpec.describe ClaudeMemory::Commands::MetricsCalculator do
  let(:store) { instance_double(ClaudeMemory::Store::SQLiteStore) }
  let(:metrics_dataset) { double("metrics_dataset") }
  let(:calculator) { described_class.new(store) }

  before do
    allow(store).to receive(:ingestion_metrics).and_return(metrics_dataset)
  end

  describe "#calculate" do
    context "with data" do
      before do
        allow(metrics_dataset).to receive(:sum).with(:input_tokens).and_return(2000)
        allow(metrics_dataset).to receive(:sum).with(:output_tokens).and_return(1000)
        allow(metrics_dataset).to receive(:sum).with(:facts_extracted).and_return(20)
      end

      it "calculates efficiency correctly" do
        result = calculator.calculate
        expect(result[:efficiency]).to eq(10.0)  # 20 facts / 2000 tokens * 1000
      end
    end

    context "with zero tokens" do
      before do
        allow(metrics_dataset).to receive(:sum).and_return(0)
      end

      it "returns zero efficiency without dividing by zero" do
        result = calculator.calculate
        expect(result[:efficiency]).to eq(0.0)
      end
    end
  end
end
```

**Time Estimate**: 30-40 minutes (includes formatter extraction)

---

### Pattern 3: Adding Columns to Existing Table

**Use Case**: Session metadata, enhanced tracking

**Recipe:**
```ruby
# 1. Increment schema version
SCHEMA_VERSION = 8

# 2. Add migration
def migrate_to_v8!
  @db.alter_table :content_items do
    add_column :git_branch, String
    add_column :cwd, String
    add_column :claude_version, String
  end
end

# 3. Create parameter object for content item data
# ✅ Sandi Metz: Parameter object reduces method signature complexity
# lib/claude_memory/domain/content_item_params.rb
module ClaudeMemory
  module Domain
    class ContentItemParams
      attr_reader :source, :text_hash, :byte_len, :session_id,
                  :transcript_path, :git_branch, :cwd, :claude_version

      def initialize(source:, text_hash:, byte_len:, **optional)
        @source = source
        @text_hash = text_hash
        @byte_len = byte_len
        @session_id = optional[:session_id]
        @transcript_path = optional[:transcript_path]
        @git_branch = optional[:git_branch]
        @cwd = optional[:cwd]
        @claude_version = optional[:claude_version]

        freeze  # ✅ Gary Bernhardt: Immutable value object
      end

      def to_h
        {
          source: source,
          text_hash: text_hash,
          byte_len: byte_len,
          session_id: session_id,
          transcript_path: transcript_path,
          git_branch: git_branch,
          cwd: cwd,
          claude_version: claude_version,
          ingested_at: Time.now.utc  # ✅ Jeremy Evans: Use Time object
        }
      end
    end
  end
end

# 4. Update insert method to use parameter object
def upsert_content_item(params)
  # ✅ Avdi Grimm: Accept parameter object or hash
  params = Domain::ContentItemParams.new(**params) unless params.is_a?(Domain::ContentItemParams)

  @db[:content_items].insert_conflict(
    target: [:session_id, :text_hash],
    update: { ingested_at: Sequel.function(:datetime, 'now') }
  ).insert(params.to_h)
end
```

**Expert Notes:**
- ✅ **Sandi Metz**: Parameter object eliminates long parameter lists
- ✅ **Gary Bernhardt**: Immutable value object (frozen)
- ✅ **Jeremy Evans**: Use Time objects instead of ISO8601 strings
- ✅ **Avdi Grimm**: Duck typing - accepts object or hash

**Tests:**
```ruby
RSpec.describe ClaudeMemory::Domain::ContentItemParams do
  describe "#initialize" do
    it "accepts required parameters" do
      params = described_class.new(
        source: "test",
        text_hash: "abc123",
        byte_len: 100
      )

      expect(params.source).to eq("test")
      expect(params.text_hash).to eq("abc123")
      expect(params.byte_len).to eq(100)
    end

    it "accepts optional parameters" do
      params = described_class.new(
        source: "test",
        text_hash: "abc123",
        byte_len: 100,
        git_branch: "main",
        cwd: "/path/to/project"
      )

      expect(params.git_branch).to eq("main")
      expect(params.cwd).to eq("/path/to/project")
    end

    it "creates immutable object" do
      params = described_class.new(
        source: "test",
        text_hash: "abc123",
        byte_len: 100
      )

      expect(params).to be_frozen
    end
  end

  describe "#to_h" do
    it "converts to hash with timestamp" do
      params = described_class.new(
        source: "test",
        text_hash: "abc123",
        byte_len: 100,
        git_branch: "feature/test"
      )

      hash = params.to_h

      expect(hash[:source]).to eq("test")
      expect(hash[:git_branch]).to eq("feature/test")
      expect(hash[:ingested_at]).to be_a(Time)
    end
  end
end

RSpec.describe "upsert_content_item with new columns" do
  it "stores metadata using parameter object" do
    params = ClaudeMemory::Domain::ContentItemParams.new(
      source: "test",
      text_hash: "abc123",
      byte_len: 100,
      git_branch: "feature/test",
      cwd: "/path/to/project"
    )

    id = store.upsert_content_item(params)
    item = store.content_items.where(id: id).first

    expect(item[:git_branch]).to eq("feature/test")
    expect(item[:cwd]).to eq("/path/to/project")
  end

  it "accepts hash for backward compatibility" do
    id = store.upsert_content_item(
      source: "test",
      text_hash: "def456",
      byte_len: 200,
      git_branch: "main"
    )

    item = store.content_items.where(id: id).first
    expect(item[:git_branch]).to eq("main")
  end
end
```

**Time Estimate**: 20-25 minutes (includes parameter object)

---

### Pattern 4: Enhancing Statistics Output

**Use Case**: Better reporting, ROI metrics, aggregations

**Recipe:**
```ruby
# ✅ Gary Bernhardt: Pure statistics calculator, no I/O
# lib/claude_memory/domain/statistics_calculator.rb
module ClaudeMemory
  module Domain
    class StatisticsCalculator
      def initialize(metrics_data)
        @metrics_data = metrics_data
        freeze
      end

      def calculate
        Statistics.new(
          total_input_tokens: total_input_tokens,
          total_output_tokens: total_output_tokens,
          total_facts: total_facts,
          efficiency: efficiency
        )
      end

      private

      def total_input_tokens
        @metrics_data.sum { |m| m[:input_tokens] }
      end

      def total_output_tokens
        @metrics_data.sum { |m| m[:output_tokens] }
      end

      def total_facts
        @metrics_data.sum { |m| m[:facts_extracted] }
      end

      def efficiency
        return 0.0 if total_input_tokens.zero?

        (total_facts.to_f / total_input_tokens * 1000).round(2)
      end
    end

    # ✅ Avdi Grimm: Result object instead of hash
    class Statistics
      attr_reader :total_input_tokens, :total_output_tokens, :total_facts, :efficiency

      def initialize(total_input_tokens:, total_output_tokens:, total_facts:, efficiency:)
        @total_input_tokens = total_input_tokens
        @total_output_tokens = total_output_tokens
        @total_facts = total_facts
        @efficiency = efficiency
        freeze
      end

      def efficient?
        efficiency > 5.0  # More than 5 facts per 1k tokens
      end

      def to_h
        {
          total_input_tokens: total_input_tokens,
          total_output_tokens: total_output_tokens,
          total_facts: total_facts,
          efficiency: efficiency
        }
      end
    end
  end
end

# ✅ Sandi Metz: Small methods, single responsibility
# lib/claude_memory/commands/stats_command.rb
module ClaudeMemory
  module Commands
    class StatsCommand < BaseCommand
      def call(args)
        manager = Store::StoreManager.new

        display_basic_stats(manager)
        display_metrics_stats(manager) if has_metrics?(manager)

        0
      ensure
        manager&.close
      end

      private

      def display_basic_stats(manager)
        stdout.puts "Facts: #{count_facts(manager)}"
        stdout.puts "Entities: #{count_entities(manager)}"
      end

      def display_metrics_stats(manager)
        stats = calculate_statistics(manager)
        formatter = StatisticsFormatter.new(stdout)
        formatter.format(stats)
      end

      def has_metrics?(manager)
        manager.global_store.db.table_exists?(:ingestion_metrics)
      end

      def calculate_statistics(manager)
        metrics_data = manager.global_store.ingestion_metrics.all
        Domain::StatisticsCalculator.new(metrics_data).calculate
      end

      def count_facts(manager)
        manager.global_store.facts.count
      end

      def count_entities(manager)
        manager.global_store.entities.count
      end
    end

    # ✅ Sandi Metz: Formatter has single responsibility
    class StatisticsFormatter
      def initialize(output)
        @output = output
      end

      def format(statistics)
        @output.puts "\nToken Economics:"
        @output.puts "  Input tokens:    #{statistics.total_input_tokens}"
        @output.puts "  Output tokens:   #{statistics.total_output_tokens}"
        @output.puts "  Facts extracted: #{statistics.total_facts}"
        @output.puts "  Efficiency:      #{statistics.efficiency} facts/1k tokens"
        @output.puts "  Status:          #{efficiency_status(statistics)}"
      end

      private

      def efficiency_status(statistics)
        statistics.efficient? ? "Good" : "Could be improved"
      end
    end
  end
end
```

**Expert Notes:**
- ✅ **Gary Bernhardt**: Pure calculator (no I/O), data passed in
- ✅ **Avdi Grimm**: Statistics result object with behavior (efficient?)
- ✅ **Sandi Metz**: Small classes with single responsibility
- ✅ **Kent Beck**: Calculator can be tested without database

**Tests:**
```ruby
RSpec.describe ClaudeMemory::Domain::StatisticsCalculator do
  describe "#calculate" do
    let(:metrics_data) do
      [
        { input_tokens: 1000, output_tokens: 500, facts_extracted: 10 },
        { input_tokens: 2000, output_tokens: 1000, facts_extracted: 15 }
      ]
    end

    it "calculates totals correctly" do
      calculator = described_class.new(metrics_data)
      stats = calculator.calculate

      expect(stats.total_input_tokens).to eq(3000)
      expect(stats.total_output_tokens).to eq(1500)
      expect(stats.total_facts).to eq(25)
    end

    it "calculates efficiency as facts per 1k tokens" do
      calculator = described_class.new(metrics_data)
      stats = calculator.calculate

      # 25 facts / 3000 tokens * 1000 = 8.33
      expect(stats.efficiency).to eq(8.33)
    end

    context "with no data" do
      it "returns zero efficiency" do
        calculator = described_class.new([])
        stats = calculator.calculate

        expect(stats.efficiency).to eq(0.0)
      end
    end
  end
end

RSpec.describe ClaudeMemory::Domain::Statistics do
  describe "#efficient?" do
    it "returns true when efficiency > 5.0" do
      stats = described_class.new(
        total_input_tokens: 1000,
        total_output_tokens: 500,
        total_facts: 10,
        efficiency: 10.0
      )

      expect(stats).to be_efficient
    end

    it "returns false when efficiency <= 5.0" do
      stats = described_class.new(
        total_input_tokens: 1000,
        total_output_tokens: 500,
        total_facts: 3,
        efficiency: 3.0
      )

      expect(stats).not_to be_efficient
    end
  end
end
```

**Time Estimate**: 30-35 minutes (includes result object)

---

### Pattern 5: Adding Command Line Flags

**Use Case**: --async, --verbose, --format options

**Recipe:**
```ruby
# ✅ Sandi Metz: Small, focused methods
module ClaudeMemory
  module Commands
    class ConfigurableCommand < BaseCommand
      def call(args)
        opts = parse_options(args)
        return 1 if opts.nil?

        execute_with_options(opts)
      end

      private

      def parse_options(args)
        opts = default_options

        OptionParser.new do |parser|
          configure_parser(parser, opts)
        end.parse!(args)

        opts
      rescue OptionParser::InvalidOption => e
        stderr.puts "Error: #{e.message}"
        nil
      end

      def configure_parser(parser, opts)
        parser.banner = "Usage: claude-memory command [options]"
        parser.on("--async", "Run in background") { opts[:async] = true }
        parser.on("--verbose", "Verbose output") { opts[:verbose] = true }
        parser.on("--format FORMAT", ["text", "json"], "Output format") do |f|
          opts[:format] = f
        end
      end

      def default_options
        { async: false, verbose: false, format: "text" }
      end

      # ✅ Kent Beck: Method name reveals intent
      def execute_with_options(opts)
        if opts[:async]
          execute_in_background(opts)
        else
          execute_synchronously(opts)
        end
      end

      def execute_in_background(opts)
        BackgroundExecutor.new(stdout).execute do
          perform_work(opts)
        end
        0
      end

      def execute_synchronously(opts)
        result = perform_work(opts)
        output_result(result, opts)
        0
      end

      def perform_work(opts)
        # Actual work implementation
      end

      def output_result(result, opts)
        # Output formatting
      end
    end

    # ✅ Sandi Metz: Extract background execution to separate class
    class BackgroundExecutor
      def initialize(output)
        @output = output
      end

      def execute(&block)
        pid = Process.fork(&block)
        Process.detach(pid)
        @output.puts "Running in background (PID: #{pid})"
      rescue NotImplementedError
        # Windows doesn't support fork
        @output.puts "Background execution not supported on this platform"
        block.call
      end
    end
  end
end
```

**Expert Notes:**
- ✅ **Sandi Metz**: Small methods, background executor extracted
- ✅ **Kent Beck**: Clear method names (execute_in_background vs execute_synchronously)
- ✅ **Gary Bernhardt**: Separation of concerns

**Tests:**
```ruby
RSpec.describe ClaudeMemory::Commands::BackgroundExecutor do
  let(:output) { StringIO.new }
  let(:executor) { described_class.new(output) }

  describe "#execute" do
    it "forks process and reports PID" do
      allow(Process).to receive(:fork).and_yield.and_return(12345)
      allow(Process).to receive(:detach)

      work_done = false
      executor.execute { work_done = true }

      expect(work_done).to be true
      expect(output.string).to include("PID: 12345")
      expect(Process).to have_received(:detach).with(12345)
    end

    context "on Windows" do
      it "executes synchronously when fork not available" do
        allow(Process).to receive(:fork).and_raise(NotImplementedError)

        work_done = false
        executor.execute { work_done = true }

        expect(work_done).to be true
        expect(output.string).to include("not supported")
      end
    end
  end
end
```

**Time Estimate**: 20-25 minutes

---

### Pattern 6: Background Processing (Simple Fork)

**Use Case**: Non-blocking hook execution

**Recipe:**
```ruby
# lib/claude_memory/commands/hook_ingest_command.rb
module ClaudeMemory
  module Commands
    class HookIngestCommand < BaseCommand
      def call(args)
        opts = parse_options(args)
        return 1 if opts.nil?

        payload = read_stdin

        if opts[:async]
          execute_async(payload, opts)
        else
          execute_sync(payload, opts)
        end
      end

      private

      def execute_async(payload, opts)
        # ✅ Gary Bernhardt: Use Configuration for paths
        log_path = LogPath.for_async_operation

        BackgroundIngester.new(log_path, stdout).ingest(payload)
        0
      rescue => e
        stderr.puts "Failed to start background process: #{e.message}"
        1
      end

      def execute_sync(payload, opts)
        result = perform_ingestion(payload)
        stdout.puts "Ingested: #{result.facts_count} facts"
        0
      end

      def perform_ingestion(payload)
        manager = Store::StoreManager.new
        ingester = Ingest::Ingester.new(manager)
        result = ingester.ingest(payload)
        manager.close
        result
      end
    end

    # ✅ Sandi Metz: Extract background logic to separate class
    class BackgroundIngester
      def initialize(log_path, output)
        @log_path = log_path
        @output = output
      end

      def ingest(payload)
        pid = fork_and_ingest(payload)
        Process.detach(pid)
        report_started(pid)
      end

      private

      def fork_and_ingest(payload)
        Process.fork do
          redirect_output_to_log
          perform_ingestion(payload)
          exit 0
        end
      end

      def redirect_output_to_log
        $stdout.reopen(@log_path, "a")
        $stderr.reopen(@log_path, "a")
      end

      def perform_ingestion(payload)
        manager = Store::StoreManager.new
        ingester = Ingest::Ingester.new(manager)
        ingester.ingest(payload)
        manager.close
      end

      def report_started(pid)
        @output.puts "Ingestion started in background (PID: #{pid})"
        @output.puts "Logs: #{@log_path}"
      end
    end

    # ✅ Gary Bernhardt: Use Configuration for path resolution
    class LogPath
      def self.for_async_operation
        if Configuration.project_dir
          File.join(Configuration.project_dir, ".claude", "memory_ingest.log")
        else
          File.join(Configuration.home_dir, ".claude", "memory_ingest.log")
        end
      end
    end
  end
end
```

**Expert Notes:**
- ✅ **Sandi Metz**: Background ingester is separate class with single responsibility
- ✅ **Gary Bernhardt**: Configuration used instead of direct ENV access
- ✅ **Kent Beck**: Small methods with clear purpose
- ✅ **Avdi Grimm**: Confident code, no nil checks needed

**Tests:**
```ruby
RSpec.describe ClaudeMemory::Commands::BackgroundIngester do
  let(:log_path) { "/tmp/test.log" }
  let(:output) { StringIO.new }
  let(:ingester) { described_class.new(log_path, output) }

  describe "#ingest" do
    let(:payload) { { transcript_delta: "test content" } }

    it "forks process and detaches" do
      allow(Process).to receive(:fork).and_yield.and_return(99999)
      allow(Process).to receive(:detach)

      # Mock the actual ingestion
      allow_any_instance_of(ClaudeMemory::Ingest::Ingester)
        .to receive(:ingest)
        .and_return(double(facts_count: 5))

      ingester.ingest(payload)

      expect(Process).to have_received(:fork)
      expect(Process).to have_received(:detach).with(99999)
      expect(output.string).to include("PID: 99999")
      expect(output.string).to include("Logs: #{log_path}")
    end
  end
end

RSpec.describe ClaudeMemory::Commands::LogPath do
  describe ".for_async_operation" do
    context "in project directory" do
      before do
        allow(ClaudeMemory::Configuration).to receive(:project_dir)
          .and_return("/path/to/project")
      end

      it "returns project log path" do
        path = described_class.for_async_operation
        expect(path).to eq("/path/to/project/.claude/memory_ingest.log")
      end
    end

    context "outside project directory" do
      before do
        allow(ClaudeMemory::Configuration).to receive(:project_dir).and_return(nil)
        allow(ClaudeMemory::Configuration).to receive(:home_dir).and_return("/home/user")
      end

      it "returns home directory log path" do
        path = described_class.for_async_operation
        expect(path).to eq("/home/user/.claude/memory_ingest.log")
      end
    end
  end
end
```

**Important Notes:**
- Test fork behavior with mocks
- Windows doesn't support fork (consider fallback)
- Always detach process to avoid zombies
- Use Configuration for path resolution

**Time Estimate**: 45-60 minutes

---

## Expert Principles Applied

### Sandi Metz (POODR)
- ✅ Small methods (< 5 lines ideal)
- ✅ Single responsibility per class
- ✅ Parameter objects for long parameter lists
- ✅ Extract formatters, calculators, executors

### Jeremy Evans (Sequel)
- ✅ DateTime columns instead of String timestamps
- ✅ Proper Sequel dataset usage
- ✅ Transaction safety where needed

### Kent Beck (TDD, Simple Design)
- ✅ Method names reveal intent
- ✅ Testable design (dependency injection)
- ✅ Test edge cases (zero values, errors)

### Avdi Grimm (Confident Ruby)
- ✅ Result objects instead of hashes
- ✅ No nil checks (use null objects if needed)
- ✅ Duck typing (accept object or hash)
- ✅ Immutable value objects (frozen)

### Gary Bernhardt (Boundaries)
- ✅ Pure calculators (no I/O in logic)
- ✅ Dependency injection for testability
- ✅ Configuration class for ENV access
- ✅ Ensure resource cleanup (ensure blocks)

---

## Feature Complexity Assessment

### Quick Assessment Checklist

**Low Complexity** (15-30 min):
- [ ] Pure Ruby, no external dependencies
- [ ] Clear, well-defined requirements
- [ ] Existing patterns to follow
- [ ] Straightforward testing

**Medium Complexity** (30-60 min):
- [ ] Requires new gem dependency
- [ ] Some architectural decisions needed
- [ ] Background processing (simple fork)
- [ ] Multiple files affected

**High Complexity** (60+ min or skip):
- [ ] External services required
- [ ] Daemon/worker management
- [ ] Web UI components
- [ ] Cross-platform compatibility issues
- [ ] Security-critical code

### Common Pitfalls & Solutions

1. **String Timestamps**
   - ❌ Problem: `String :created_at`
   - ✅ Solution: `DateTime :created_at`

2. **Direct ENV Access**
   - ❌ Problem: `ENV["CLAUDE_PROJECT_DIR"]`
   - ✅ Solution: `Configuration.project_dir`

3. **Long Parameter Lists**
   - ❌ Problem: 7+ parameters
   - ✅ Solution: Parameter object

4. **Creating Dependencies in Methods**
   - ❌ Problem: `store = Store.new` inside method
   - ✅ Solution: Inject dependency

5. **No Resource Cleanup**
   - ❌ Problem: `manager.close` can be skipped
   - ✅ Solution: `ensure` block

6. **Nil Checks Everywhere**
   - ❌ Problem: `return nil unless x`
   - ✅ Solution: Result objects or null objects

7. **Mixed I/O and Logic**
   - ❌ Problem: Database queries in calculator
   - ✅ Solution: Pass data to pure calculator

8. **Vague Method Names**
   - ❌ Problem: `do_something`, `process`
   - ✅ Solution: `calculate_efficiency`, `execute_in_background`

---

## When to Split into Multiple Commits

**Split when:**
- Schema change + feature implementation (2 commits)
- Core feature + CLI command (2 commits)
- Multiple independent enhancements (separate commits)

**Keep together when:**
- Feature + tests (same commit)
- Command + help text (same commit)
- Implementation + error handling (same commit)
- Parameter object + method using it (same commit)

---

## Testing Strategies

### Pure Calculators (Fast)
```ruby
# No mocks needed - pure logic
it "calculates efficiency" do
  calculator = StatisticsCalculator.new(data)
  expect(calculator.calculate.efficiency).to eq(10.0)
end
```

### Commands (With Dependency Injection)
```ruby
# Inject test doubles
let(:store_manager) { instance_double(Store::StoreManager) }
let(:command) { described_class.new(store_manager: store_manager) }

it "uses injected store manager" do
  command.call([])
  expect(store_manager).to have_received(:global_store)
end
```

### Resource Cleanup
```ruby
it "closes manager even on exception" do
  allow(store).to receive(:facts).and_raise("DB error")

  expect { command.call([]) }.to raise_error("DB error")
  expect(manager).to have_received(:close)
end
```

### Result Objects
```ruby
it "returns statistics object with behavior" do
  stats = calculator.calculate

  expect(stats).to respond_to(:efficient?)
  expect(stats.efficient?).to be true
end
```

---

**Remember:** These patterns demonstrate best practices from all five experts. Use them as templates when implementing new features with `/improve`.
