# frozen_string_literal: true

module Ferret
  module Searcher
    @mutex = Mutex.new

    def self.reranker
      @reranker || @mutex.synchronize do
        @reranker ||= begin
          require "informers"
          Informers.pipeline("reranking", Ferret.configuration.reranker_model)
        end
      end
    end

    def self.reset_models!
      @mutex.synchronize { @reranker = nil }
    end

    def self.search(model_class, query, limit: 20, rerank: nil)
      config = Ferret.configuration
      use_rerank = rerank.nil? ? config.rerank : rerank
      db = Database.connection
      record_type = model_class.name
      pool = [config.rerank_pool, limit * 2].max

      # --- Vector search ---
      embedding = Indexer.embed_model.(query)
      blob = embedding.pack("e*")

      vec_results = db.execute(<<~SQL, [blob, pool, record_type])
        SELECT v.record_type, v.record_id, vp.distance
        FROM (
          SELECT rowid, distance
          FROM vec_documents
          WHERE embedding MATCH ? AND k = ?
        ) vp
        JOIN vec_lookup v ON v.rowid = vp.rowid
        WHERE v.record_type = ?
      SQL

      # --- FTS search ---
      fts_query = query.split(/\s+/).map { |w| %("#{w}") }.join(" ")
      fts_results = begin
        db.execute(<<~SQL, [fts_query, record_type, pool])
          SELECT record_type, record_id, rank
          FROM fts_documents
          WHERE fts_documents MATCH ? AND record_type = ?
          ORDER BY rank
          LIMIT ?
        SQL
      rescue SQLite3::SQLException
        []
      end

      # --- RRF fusion ---
      scores = Hash.new(0.0)

      vec_results.each_with_index do |r, i|
        scores[r["record_id"]] += config.vec_weight / (config.rrf_k + i + 1)
      end

      fts_results.each_with_index do |r, i|
        scores[r["record_id"]] += config.fts_weight / (config.rrf_k + i + 1)
      end

      candidate_ids = scores.sort_by { |_, s| -s }.first(pool).map(&:first)
      return model_class.none if candidate_ids.empty?

      # --- Fetch candidate texts for reranking ---
      if use_rerank && candidate_ids.any?
        placeholders = candidate_ids.map { "?" }.join(", ")
        candidates = db.execute(<<~SQL, [record_type] + candidate_ids)
          SELECT record_id, searchable_text
          FROM ferret_documents
          WHERE record_type = ? AND record_id IN (#{placeholders})
        SQL

        id_to_text = candidates.to_h { |c| [c["record_id"], c["searchable_text"]] }

        # Maintain order from RRF
        ordered_ids = candidate_ids.select { |id| id_to_text.key?(id) }
        docs = ordered_ids.map { |id| (id_to_text[id] || "")[0, 256] }

        if docs.any?
          reranked = reranker.(query, docs)

          scored = reranked
                   .select { |r| r[:score] > config.rerank_floor }
                   .sort_by { |r| -r[:score] }

          final_ids = scored.first(limit).map { |r| ordered_ids[r[:doc_id]] }
        else
          final_ids = candidate_ids.first(limit)
        end
      else
        final_ids = candidate_ids.first(limit)
      end

      return model_class.none if final_ids.empty?

      # Return AR records in ranked order
      records = model_class.where(id: final_ids).index_by { |r| r.id.to_s }
      final_ids.filter_map { |id| records[id] }
    end
  end
end
