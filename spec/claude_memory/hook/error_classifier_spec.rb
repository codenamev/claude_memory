# frozen_string_literal: true

RSpec.describe ClaudeMemory::Hook::ErrorClassifier do
  describe ".transport_error?" do
    it "returns true for Sequel::DatabaseError" do
      error = Sequel::DatabaseError.new("database is locked")
      expect(described_class.transport_error?(error)).to be true
    end

    it "returns true for Sequel::DatabaseConnectionError" do
      error = Sequel::DatabaseConnectionError.new("unable to open database")
      expect(described_class.transport_error?(error)).to be true
    end

    it "returns true for Errno::EACCES" do
      error = Errno::EACCES.new("/path/to/db")
      expect(described_class.transport_error?(error)).to be true
    end

    it "returns true for Errno::ENOSPC" do
      error = Errno::ENOSPC.new("disk full")
      expect(described_class.transport_error?(error)).to be true
    end

    it "returns true for IOError" do
      error = IOError.new("stream closed")
      expect(described_class.transport_error?(error)).to be true
    end

    it "returns false for PayloadError" do
      error = ClaudeMemory::Hook::Handler::PayloadError.new("missing field")
      expect(described_class.transport_error?(error)).to be false
    end

    it "returns false for TypeError" do
      error = TypeError.new("wrong type")
      expect(described_class.transport_error?(error)).to be false
    end
  end

  describe ".client_error?" do
    it "returns true for PayloadError" do
      error = ClaudeMemory::Hook::Handler::PayloadError.new("missing field")
      expect(described_class.client_error?(error)).to be true
    end

    it "returns true for TypeError" do
      error = TypeError.new("wrong type")
      expect(described_class.client_error?(error)).to be true
    end

    it "returns true for NoMethodError" do
      error = NoMethodError.new("undefined method")
      expect(described_class.client_error?(error)).to be true
    end

    it "returns true for ArgumentError" do
      error = ArgumentError.new("wrong number of arguments")
      expect(described_class.client_error?(error)).to be true
    end

    it "returns true for JSON::ParserError" do
      error = JSON::ParserError.new("unexpected token")
      expect(described_class.client_error?(error)).to be true
    end

    it "returns false for Sequel::DatabaseError" do
      error = Sequel::DatabaseError.new("locked")
      expect(described_class.client_error?(error)).to be false
    end
  end

  describe ".exit_code_for" do
    it "returns SUCCESS for transport errors" do
      error = Sequel::DatabaseError.new("database is locked")
      expect(described_class.exit_code_for(error)).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
    end

    it "returns ERROR for client errors" do
      error = TypeError.new("wrong type")
      expect(described_class.exit_code_for(error)).to eq(ClaudeMemory::Hook::ExitCodes::ERROR)
    end

    it "returns SUCCESS for unknown errors (graceful degradation)" do
      error = RuntimeError.new("something unexpected")
      expect(described_class.exit_code_for(error)).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
    end

    it "returns SUCCESS for Errno::EACCES (permission denied)" do
      error = Errno::EACCES.new("/path")
      expect(described_class.exit_code_for(error)).to eq(ClaudeMemory::Hook::ExitCodes::SUCCESS)
    end

    it "returns ERROR for PayloadError" do
      error = ClaudeMemory::Hook::Handler::PayloadError.new("bad payload")
      expect(described_class.exit_code_for(error)).to eq(ClaudeMemory::Hook::ExitCodes::ERROR)
    end
  end
end
