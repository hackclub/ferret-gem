# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ferret::Database do
  describe ".connection" do
    it "returns a SQLite3 database connection" do
      expect(described_class.connection).to be_a(SQLite3::Database)
    end

    it "uses WAL journal mode" do
      mode = described_class.connection.execute("PRAGMA journal_mode").first
      expect(mode.values).to include("wal")
    end

    it "sets busy_timeout to 5000ms" do
      timeout = described_class.connection.execute("PRAGMA busy_timeout").first
      expect(timeout.values.first).to eq(5000)
    end

    it "creates all required tables" do
      tables = described_class.connection
        .execute("SELECT name FROM sqlite_master WHERE type='table' OR type='shadow'")
        .map { |r| r["name"] }

      expect(tables).to include("ferret_documents")
      expect(tables).to include("vec_lookup")
    end

    it "returns the same connection on subsequent calls" do
      expect(described_class.connection).to be(described_class.connection)
    end
  end

  describe ".clean" do
    it "strips URLs" do
      expect(described_class.clean("visit https://example.com today")).to eq("visit today")
    end

    it "strips markdown characters" do
      expect(described_class.clean("**bold** and _italic_")).to eq("bold and italic")
    end

    it "collapses whitespace" do
      expect(described_class.clean("too   many    spaces")).to eq("too many spaces")
    end

    it "returns nil for nil input" do
      expect(described_class.clean(nil)).to be_nil
    end
  end
end
