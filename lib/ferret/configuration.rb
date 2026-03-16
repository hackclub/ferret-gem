# frozen_string_literal: true

module Ferret
  class Configuration
    attr_accessor :database_path,
                  :embedding_model,
                  :reranker_model,
                  :queue,
                  :embed_on_save,
                  :rerank,
                  :rerank_pool,
                  :rerank_floor,
                  :vec_weight,
                  :fts_weight,
                  :rrf_k

    def initialize
      @database_path = nil # set by railtie to Rails.root.join("db/ferret.sqlite3")
      @embedding_model = "sentence-transformers/all-mpnet-base-v2"
      @reranker_model = "cross-encoder/ms-marco-MiniLM-L-6-v2"
      @queue = :default
      @embed_on_save = true
      @rerank = true
      @rerank_pool = 37
      @rerank_floor = 0.01
      @vec_weight = 2.0
      @fts_weight = 1.0
      @rrf_k = 60.0
    end
  end
end
