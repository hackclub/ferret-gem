# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ferret::Searcher do
  # Known fixture data — these produce deterministic vector/reranker rankings.
  #
  # For query "game":
  #   Vector similarity (dot product): chess > game_engine > chat_app > music > weather_app
  #   Reranker scores:   game_engine(0.23) >> chess(0.003) >> music(~0) > chat_app(~0) > weather_app(~0)
  #   RRF fusion (vec*2 + fts*1): game_engine and chess should be top 2

  FIXTURES = {
    "3D Game Engine" => "A real-time 3D game engine with physics simulation",
    "Weather Dashboard" => "Real-time weather data visualization dashboard",
    "Chat Application" => "Encrypted messaging application with end-to-end security",
    "Chess Engine" => "AI-powered chess engine with move prediction",
    "Music Studio" => "Music production studio with synthesizer and drum machine"
  }.freeze

  before(:all) do
    # Delete without triggering ferret_remove callbacks
    TestProject.delete_all
    @projects = {}
    FIXTURES.each do |title, desc|
      @projects[title] = TestProject.create!(title: title, description: desc)
    end
    Ferret::Indexer.embed_all!(TestProject)
  end

  after(:all) do
    TestProject.delete_all
    db = Ferret::Database.connection
    db.execute("DELETE FROM ferret_documents")
    db.execute("DELETE FROM vec_lookup")
    db.execute("DELETE FROM vec_documents")
    db.execute("DROP TABLE IF EXISTS fts_documents")
    Ferret::Database.migrate(db)
  end

  describe ".search without reranking" do
    it "returns ActiveRecord objects" do
      results = described_class.search(TestProject, "game", limit: 5, rerank: false)
      expect(results).to all(be_a(TestProject))
    end

    it "ranks game-related results above unrelated ones" do
      results = described_class.search(TestProject, "game", limit: 5, rerank: false)
      top_2_titles = results.first(2).map(&:title)

      expect(top_2_titles).to include("3D Game Engine")
      expect(top_2_titles).to include("Chess Engine")
    end

    it "puts weather app last for query 'game'" do
      results = described_class.search(TestProject, "game", limit: 5, rerank: false)
      expect(results.last.title).to eq("Weather Dashboard")
    end

    it "respects the limit parameter" do
      results = described_class.search(TestProject, "game", limit: 2, rerank: false)
      expect(results.length).to eq(2)
    end

    it "finds weather-related content for query 'weather'" do
      results = described_class.search(TestProject, "weather forecast", limit: 5, rerank: false)
      expect(results.first.title).to eq("Weather Dashboard")
    end

    it "finds music-related content for query 'music'" do
      results = described_class.search(TestProject, "music synthesizer", limit: 5, rerank: false)
      expect(results.first.title).to eq("Music Studio")
    end
  end

  describe ".search with reranking" do
    it "returns ActiveRecord objects" do
      results = described_class.search(TestProject, "game", limit: 5, rerank: true)
      expect(results).to all(be_a(TestProject))
    end

    it "ranks '3D Game Engine' first for query 'game'" do
      # The cross-encoder gives game_engine a score of 0.23 vs chess at 0.003
      results = described_class.search(TestProject, "game", limit: 5, rerank: true)
      expect(results.first.title).to eq("3D Game Engine")
    end

    it "filters low-confidence results with rerank_floor" do
      # Default rerank_floor is 0.01. Chess scores 0.003, others even lower.
      # Only game_engine (0.23) should survive the floor.
      results = described_class.search(TestProject, "game", limit: 5, rerank: true)
      expect(results.length).to be < 5
      expect(results.map(&:title)).to include("3D Game Engine")
    end

    it "finds the right result for query 'encrypted messaging'" do
      results = described_class.search(TestProject, "encrypted messaging", limit: 5, rerank: true)
      expect(results.first.title).to eq("Chat Application")
    end
  end
end
