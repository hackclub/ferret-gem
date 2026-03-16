# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ferret::Indexer do
  let!(:project) do
    TestProject.create!(title: "Space Invaders Clone", description: "A retro arcade game built with Lua")
  end

  after(:each) do
    db = Ferret::Database.connection
    db.execute("DELETE FROM ferret_documents")
    db.execute("DELETE FROM vec_lookup")
    db.execute("DELETE FROM vec_documents")
    db.execute("DROP TABLE IF EXISTS fts_documents")
    Ferret::Database.migrate(db)
  end

  describe ".index_record" do
    it "stores the record in ferret_documents with searchable text" do
      described_class.index_record(project)

      db = Ferret::Database.connection
      doc = db.execute(
        "SELECT * FROM ferret_documents WHERE record_type = ? AND record_id = ?",
        ["TestProject", project.id.to_s]
      ).first

      expect(doc).not_to be_nil
      expect(doc["searchable_text"]).to include("Space Invaders Clone")
      expect(doc["searchable_text"]).to include("retro arcade game")
    end

    it "stores a content hash for change detection" do
      described_class.index_record(project)

      db = Ferret::Database.connection
      doc = db.execute(
        "SELECT text_hash FROM ferret_documents WHERE record_id = ?",
        [project.id.to_s]
      ).first

      expect(doc["text_hash"]).to match(/\A[a-f0-9]{64}\z/)
    end

    it "creates a vector embedding (768 dimensions)" do
      described_class.index_record(project)

      db = Ferret::Database.connection
      lookup = db.execute(
        "SELECT rowid FROM vec_lookup WHERE record_id = ?",
        [project.id.to_s]
      ).first

      vec_row = db.execute(
        "SELECT length(embedding) as byte_len FROM vec_documents WHERE rowid = ?",
        [lookup["rowid"]]
      ).first

      # 768 floats * 4 bytes each = 3072 bytes
      expect(vec_row["byte_len"]).to eq(768 * 4)
    end

    it "creates an FTS entry" do
      described_class.index_record(project)

      db = Ferret::Database.connection
      fts = db.execute(
        "SELECT * FROM fts_documents WHERE record_type = ? AND record_id = ?",
        ["TestProject", project.id.to_s]
      ).first

      expect(fts).not_to be_nil
      expect(fts["searchable_text"]).to include("Space Invaders Clone")
    end

    it "skips re-embedding when content hasn't changed" do
      described_class.index_record(project)

      db = Ferret::Database.connection
      ts1 = db.execute(
        "SELECT updated_at FROM ferret_documents WHERE record_id = ?",
        [project.id.to_s]
      ).first["updated_at"]

      sleep 1.1
      described_class.index_record(project)

      ts2 = db.execute(
        "SELECT updated_at FROM ferret_documents WHERE record_id = ?",
        [project.id.to_s]
      ).first["updated_at"]

      expect(ts2).to eq(ts1)
    end

    it "re-embeds when content changes" do
      described_class.index_record(project)
      project.update!(title: "Totally Different Project")
      described_class.index_record(project)

      db = Ferret::Database.connection
      doc = db.execute(
        "SELECT searchable_text FROM ferret_documents WHERE record_id = ?",
        [project.id.to_s]
      ).first

      expect(doc["searchable_text"]).to include("Totally Different Project")
      expect(doc["searchable_text"]).not_to include("Space Invaders")
    end

    it "skips records with blank searchable text" do
      empty = TestProject.create!(title: "", description: "")
      described_class.index_record(empty)

      db = Ferret::Database.connection
      doc = db.execute(
        "SELECT * FROM ferret_documents WHERE record_id = ?",
        [empty.id.to_s]
      ).first

      expect(doc).to be_nil
    end
  end

  describe ".remove_record" do
    it "removes the record from all ferret tables" do
      described_class.index_record(project)
      described_class.remove_record("TestProject", project.id.to_s)

      db = Ferret::Database.connection
      expect(db.execute("SELECT COUNT(*) as c FROM ferret_documents WHERE record_id = ?",
                        [project.id.to_s]).first["c"]).to eq(0)
      expect(db.execute("SELECT COUNT(*) as c FROM vec_lookup WHERE record_id = ?",
                        [project.id.to_s]).first["c"]).to eq(0)
    end
  end

  describe ".embed_all!" do
    it "indexes every record with non-blank searchable text" do
      TestProject.delete_all
      TestProject.create!(title: "Chess Engine", description: "AI-powered chess")
      TestProject.create!(title: "Weather App", description: "Shows the forecast")
      TestProject.create!(title: "", description: "") # blank — should be skipped

      described_class.embed_all!(TestProject)

      db = Ferret::Database.connection
      count = db.execute(
        "SELECT COUNT(*) as c FROM ferret_documents WHERE record_type = 'TestProject'"
      ).first["c"]

      # 2 indexed, not 3 — the blank one is skipped
      expect(count).to eq(2)
    end
  end
end
