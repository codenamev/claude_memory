# frozen_string_literal: true

RSpec.describe ClaudeMemory::Core::Result do
  describe ".success" do
    it "creates Success with value" do
      result = described_class.success(42)
      expect(result).to be_success
      expect(result.value).to eq(42)
      expect(result.error).to be_nil
    end

    it "creates Success with nil value" do
      result = described_class.success
      expect(result).to be_success
      expect(result.value).to be_nil
    end

    it "creates Success that is not a failure" do
      result = described_class.success(42)
      expect(result).not_to be_failure
    end
  end

  describe ".failure" do
    it "creates Failure with error message" do
      result = described_class.failure("Something went wrong")
      expect(result).to be_failure
      expect(result.error).to eq("Something went wrong")
    end

    it "creates Failure that is not a success" do
      result = described_class.failure("Error")
      expect(result).not_to be_success
    end

    it "raises error when trying to access value" do
      result = described_class.failure("Error")
      expect {
        result.value
      }.to raise_error(RuntimeError, /Cannot get value from Failure/)
    end
  end

  describe "pattern matching" do
    it "can be used with case/when" do
      result = described_class.success(100)
      output = case result
      when ClaudeMemory::Core::Success
        "got #{result.value}"
      when ClaudeMemory::Core::Failure
        "error: #{result.error}"
      end
      expect(output).to eq("got 100")
    end

    it "can match failures" do
      result = described_class.failure("bad things")
      output = case result
      when ClaudeMemory::Core::Success
        "got #{result.value}"
      when ClaudeMemory::Core::Failure
        "error: #{result.error}"
      end
      expect(output).to eq("error: bad things")
    end
  end

  describe "immutability" do
    it "Success objects are frozen" do
      result = described_class.success(42)
      expect(result).to be_frozen
    end

    it "Failure objects are frozen" do
      result = described_class.failure("error")
      expect(result).to be_frozen
    end
  end

  describe "#map" do
    it "transforms success value" do
      result = described_class.success(5)
      mapped = result.map { |v| v * 2 }
      expect(mapped).to be_success
      expect(mapped.value).to eq(10)
    end

    it "skips transformation for failure" do
      result = described_class.failure("error")
      mapped = result.map { |v| v * 2 }
      expect(mapped).to be_failure
      expect(mapped.error).to eq("error")
    end
  end

  describe "#flat_map" do
    it "chains successful operations" do
      result = described_class.success(5)
      chained = result.flat_map { |v| described_class.success(v * 2) }
      expect(chained).to be_success
      expect(chained.value).to eq(10)
    end

    it "propagates failure in chain" do
      result = described_class.success(5)
      chained = result.flat_map { |v| described_class.failure("error") }
      expect(chained).to be_failure
      expect(chained.error).to eq("error")
    end

    it "skips operation for initial failure" do
      result = described_class.failure("first error")
      chained = result.flat_map { |v| described_class.success(v * 2) }
      expect(chained).to be_failure
      expect(chained.error).to eq("first error")
    end
  end

  describe "#or_else" do
    it "returns value for success" do
      result = described_class.success(42)
      expect(result.or_else(0)).to eq(42)
    end

    it "returns default for failure" do
      result = described_class.failure("error")
      expect(result.or_else(0)).to eq(0)
    end
  end
end
