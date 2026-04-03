# frozen_string_literal: true

RSpec.describe ClaudeMemory::Core::CategoryInference do
  describe ".infer" do
    it "maps decision predicate to decision category" do
      expect(described_class.infer("decision")).to eq("decision")
    end

    it "maps decided_ prefix to decision category" do
      expect(described_class.infer("decided_to_use_redis")).to eq("decision")
    end

    it "maps convention predicate to convention category" do
      expect(described_class.infer("convention")).to eq("convention")
    end

    it "maps _convention suffix to convention category" do
      expect(described_class.infer("naming_convention")).to eq("convention")
    end

    it "maps uses_database to architecture category" do
      expect(described_class.infer("uses_database")).to eq("architecture")
    end

    it "maps uses_framework to architecture category" do
      expect(described_class.infer("uses_framework")).to eq("architecture")
    end

    it "maps deployment_platform to architecture category" do
      expect(described_class.infer("deployment_platform")).to eq("architecture")
    end

    it "maps testing_framework to architecture category" do
      expect(described_class.infer("testing_framework")).to eq("architecture")
    end

    it "maps depends_on to dependency category" do
      expect(described_class.infer("depends_on")).to eq("dependency")
    end

    it "maps prefers to preference category" do
      expect(described_class.infer("prefers")).to eq("preference")
    end

    it "maps avoids to preference category" do
      expect(described_class.infer("avoids")).to eq("preference")
    end

    it "maps unknown predicates to general" do
      expect(described_class.infer("random_stuff")).to eq("general")
    end

    it "uses pattern matching for uses_ prefix" do
      expect(described_class.infer("uses_orm")).to eq("architecture")
    end

    it "uses pattern matching for constraint_ prefix" do
      expect(described_class.infer("constraint_max_size")).to eq("constraint")
    end

    it "prefers explicit category over inferred" do
      expect(described_class.infer("uses_database", explicit_category: "decision")).to eq("decision")
    end

    it "ignores invalid explicit category" do
      expect(described_class.infer("uses_database", explicit_category: "bogus")).to eq("architecture")
    end
  end

  describe ".valid?" do
    it "returns true for valid categories" do
      %w[decision convention architecture preference constraint dependency general].each do |cat|
        expect(described_class.valid?(cat)).to be true
      end
    end

    it "returns false for invalid categories" do
      expect(described_class.valid?("bogus")).to be false
    end
  end
end
