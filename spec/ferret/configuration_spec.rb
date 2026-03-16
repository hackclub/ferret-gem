# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ferret::Configuration do
  subject(:config) { described_class.new }

  it "uses all-mpnet-base-v2 as the default embedding model" do
    expect(config.embedding_model).to eq("sentence-transformers/all-mpnet-base-v2")
  end

  it "uses ms-marco-MiniLM as the default reranker model" do
    expect(config.reranker_model).to eq("cross-encoder/ms-marco-MiniLM-L-6-v2")
  end

  it "defaults to the :default queue" do
    expect(config.queue).to eq(:default)
  end

  it "enables embed_on_save by default" do
    expect(config.embed_on_save).to be true
  end

  it "enables reranking by default" do
    expect(config.rerank).to be true
  end

  it "sets RRF fusion weights" do
    expect(config.vec_weight).to eq(2.0)
    expect(config.fts_weight).to eq(1.0)
    expect(config.rrf_k).to eq(60.0)
  end

  it "sets rerank parameters" do
    expect(config.rerank_pool).to eq(37)
    expect(config.rerank_floor).to eq(0.01)
  end
end
