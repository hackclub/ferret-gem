# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ferret::EmbedRecordJob do
  let!(:project) { TestProject.create!(title: "Job Test Project", description: "For testing the embed job") }

  after(:each) do
    db = Ferret::Database.connection
    db.execute("DELETE FROM ferret_documents WHERE record_type = 'TestProject' AND record_id = ?", [project.id.to_s])
    db.execute("DELETE FROM vec_lookup WHERE record_type = 'TestProject' AND record_id = ?", [project.id.to_s])
  end

  it "indexes the record into the sidecar database" do
    described_class.new.perform("TestProject", project.id)

    db = Ferret::Database.connection
    doc = db.execute(
      "SELECT searchable_text FROM ferret_documents WHERE record_type = ? AND record_id = ?",
      ["TestProject", project.id.to_s]
    ).first

    expect(doc).not_to be_nil
    expect(doc["searchable_text"]).to include("Job Test Project")
  end

  it "silently skips deleted records" do
    project.delete # use delete to avoid callbacks
    expect { described_class.new.perform("TestProject", project.id) }.not_to raise_error
  end

  it "uses the configured queue" do
    Ferret.configuration.queue = :search_indexing
    job = described_class.new
    expect(job.queue_name).to eq("search_indexing")
  ensure
    Ferret.configuration.queue = :default
  end
end
