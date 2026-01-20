# frozen_string_literal: true

RSpec.describe ClaudeMemory::Distill::NullDistiller do
  let(:distiller) { described_class.new }

  describe "#distill" do
    it "returns an Extraction object" do
      result = distiller.distill("Some text content")
      expect(result).to be_a(ClaudeMemory::Distill::Extraction)
    end

    it "returns empty extraction for plain text" do
      result = distiller.distill("Hello world")
      expect(result.empty?).to be true
    end

    context "entity extraction" do
      it "extracts database mentions" do
        result = distiller.distill("We are using PostgreSQL for our database")
        expect(result.entities).to include(hash_including(type: "database", name: "postgresql"))
      end

      it "extracts framework mentions" do
        result = distiller.distill("The app is built with Rails")
        expect(result.entities).to include(hash_including(type: "framework", name: "rails"))
      end

      it "extracts platform mentions" do
        result = distiller.distill("Deployed to AWS using Terraform")
        expect(result.entities).to include(hash_including(type: "platform", name: "aws"))
      end

      it "extracts multiple entities" do
        result = distiller.distill("Rails app with PostgreSQL on AWS")
        expect(result.entities.size).to eq(3)
      end
    end

    context "fact extraction" do
      it "creates uses_database fact for database entities" do
        result = distiller.distill("Using PostgreSQL")
        expect(result.facts).to include(hash_including(predicate: "uses_database", object: "postgresql"))
      end

      it "creates deployment_platform fact for platform entities" do
        result = distiller.distill("Deployed on AWS")
        expect(result.facts).to include(hash_including(predicate: "deployment_platform", object: "aws"))
      end

      it "includes quote in fact" do
        result = distiller.distill("Using PostgreSQL for the main database")
        expect(result.facts.first[:quote]).to include("PostgreSQL")
      end
    end

    context "decision extraction" do
      it "extracts 'decided to' patterns" do
        result = distiller.distill("We decided to use snake_case for all variables")
        expect(result.decisions).to include(hash_including(title: a_string_matching(/snake_case/)))
      end

      it "extracts 'agreed to' patterns" do
        result = distiller.distill("We agreed to deploy on Fridays only")
        expect(result.decisions).to include(hash_including(summary: a_string_matching(/deploy on Fridays/)))
      end

      it "limits to 5 decisions" do
        text = Array.new(10) { |i| "We decided to do thing #{i}." }.join(" ")
        result = distiller.distill(text)
        expect(result.decisions.size).to be <= 5
      end
    end

    context "signal extraction" do
      it "detects supersession signals" do
        result = distiller.distill("We no longer use MySQL")
        expect(result.signals).to include(hash_including(kind: "supersession", value: true))
      end

      it "detects conflict signals" do
        result = distiller.distill("I disagree with that approach")
        expect(result.signals).to include(hash_including(kind: "conflict", value: true))
      end

      it "detects global scope signals from 'I always'" do
        result = distiller.distill("I always use PostgreSQL for databases")
        expect(result.signals).to include(hash_including(kind: "global_scope", value: true))
      end

      it "detects global scope signals from 'in all projects'" do
        result = distiller.distill("In all my projects I use Rails")
        expect(result.signals).to include(hash_including(kind: "global_scope", value: true))
      end

      it "detects global scope signals from 'everywhere'" do
        result = distiller.distill("I use vim bindings everywhere")
        expect(result.signals).to include(hash_including(kind: "global_scope", value: true))
      end

      it "detects global scope signals from 'my preference'" do
        result = distiller.distill("My preference is to use tabs")
        expect(result.signals).to include(hash_including(kind: "global_scope", value: true))
      end
    end

    context "scope hint in facts" do
      it "sets scope_hint to global when global signal present" do
        result = distiller.distill("I always use PostgreSQL for everything")
        expect(result.facts.first[:scope_hint]).to eq("global")
      end

      it "sets scope_hint to project by default" do
        result = distiller.distill("We use PostgreSQL here")
        expect(result.facts.first[:scope_hint]).to eq("project")
      end
    end
  end
end
