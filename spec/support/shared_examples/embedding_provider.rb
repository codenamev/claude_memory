# frozen_string_literal: true

RSpec.shared_examples "an embedding provider" do
  it "responds to #name and returns a string" do
    expect(subject.name).to be_a(String)
    expect(subject.name).not_to be_empty
  end

  it "responds to #dimensions and returns a positive integer" do
    expect(subject.dimensions).to be_a(Integer)
    expect(subject.dimensions).to be > 0
  end

  it "responds to #generate and returns an array of floats with correct dimensions" do
    result = subject.generate("test query text")
    expect(result).to be_an(Array)
    expect(result.size).to eq(subject.dimensions)
    expect(result).to all(be_a(Float).or(be_a(Integer)))
  end

  it "returns a zero vector for nil input" do
    result = subject.generate(nil)
    expect(result).to be_an(Array)
    expect(result.size).to eq(subject.dimensions)
  end

  it "returns a zero vector for empty input" do
    result = subject.generate("")
    expect(result).to be_an(Array)
    expect(result.size).to eq(subject.dimensions)
  end
end
