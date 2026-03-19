# frozen_string_literal: true

require "spec_helper"
require_relative "../../support/shared_examples/embedding_provider"

RSpec.describe ClaudeMemory::Embeddings::Generator do
  subject { described_class.new }

  it_behaves_like "an embedding provider"

  it "has name 'tfidf'" do
    expect(subject.name).to eq("tfidf")
  end

  it "has 384 dimensions" do
    expect(subject.dimensions).to eq(384)
  end
end
