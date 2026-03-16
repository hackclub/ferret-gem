# frozen_string_literal: true

require "digest"

module Ferret
  module Indexer
    @mutex = Mutex.new

    def self.embed_model
      @embed_model || @mutex.synchronize do
        @embed_model ||= begin
          require "informers"
          Informers.pipeline("embedding", Ferret.configuration.embedding_model)
        end
      end
    end

    def self.reset_models!
      @mutex.synchronize { @embed_model = nil }
    end

    def self.index_record(record)
      db = Database.connection
      record_id = record.id.to_s

      # Walk up the ancestry to find the registered base class (handles STI)
      registered_class = record.class.ancestors.detect { |klass| Ferret.registry.key?(klass) }
      return unless registered_class

      record_type = registered_class.name
      fields = Ferret.registry[registered_class]

      raw_text = fields.map { |f| record.send(f).to_s }.join(" ")
      clean_text = Database.clean(raw_text)
      return if clean_text.nil? || clean_text.strip.empty?

      text_hash = Digest::SHA256.hexdigest(clean_text)

      # Check if already indexed with same content
      existing = db.execute(
        "SELECT text_hash FROM ferret_documents WHERE record_type = ? AND record_id = ?",
        [record_type, record_id]
      ).first
      return if existing && existing["text_hash"] == text_hash

      # Embed (CPU-intensive, done outside the write lock)
      embedding = embed_model.(clean_text)
      blob = embedding.pack("e*")

      Database.with_write_lock do
        db.transaction do
          # Upsert document
          db.execute(<<~SQL, [record_type, record_id, clean_text, text_hash])
            INSERT INTO ferret_documents (record_type, record_id, searchable_text, text_hash, updated_at)
            VALUES (?, ?, ?, ?, datetime('now'))
            ON CONFLICT(record_type, record_id) DO UPDATE SET
              searchable_text = excluded.searchable_text,
              text_hash = excluded.text_hash,
              updated_at = datetime('now')
          SQL

          # Upsert vec_lookup
          db.execute(<<~SQL, [record_type, record_id])
            INSERT OR IGNORE INTO vec_lookup (record_type, record_id) VALUES (?, ?)
          SQL
          rowid = db.execute(
            "SELECT rowid FROM vec_lookup WHERE record_type = ? AND record_id = ?",
            [record_type, record_id]
          ).first["rowid"]

          # Replace vector
          db.execute("DELETE FROM vec_documents WHERE rowid = ?", [rowid])
          db.execute("INSERT INTO vec_documents (rowid, embedding) VALUES (?, ?)", [rowid, blob])

          # Replace FTS
          db.execute("DELETE FROM fts_documents WHERE record_type = ? AND record_id = ?", [record_type, record_id])
          db.execute(
            "INSERT INTO fts_documents (rowid, record_type, record_id, searchable_text) VALUES (?, ?, ?, ?)",
            [rowid, record_type, record_id, clean_text]
          )
        end
      end
    end

    BATCH_SIZE = 1000

    def self.embed_all!(model_class = nil)
      classes = if model_class
                  { model_class => Ferret.registry[model_class] }
                else
                  Ferret.registry
                end

      classes.each do |klass, fields|
        total = klass.count
        done = 0
        embedded = 0

        warn "Ferret: embedding #{total} #{klass.name} records..."

        klass.find_each(batch_size: BATCH_SIZE) do |record|
          # Resolve STI base class
          registered_class = record.class.ancestors.detect { |k| Ferret.registry.key?(k) }
          next unless registered_class

          record_type = registered_class.name
          record_id = record.id.to_s

          raw_text = fields.map { |f| record.send(f).to_s }.join(" ")
          clean_text = Database.clean(raw_text)
          done += 1

          next if clean_text.nil? || clean_text.strip.empty?

          # Collect into batch
          (@_batch ||= []) << { record_type: record_type, record_id: record_id, clean_text: clean_text }

          # Flush when batch is full or at end (handled after loop)
          if @_batch.length >= BATCH_SIZE
            embedded += flush_batch!(@_batch)
            @_batch = []
          end

          $stderr.print "\r  #{done}/#{total}" if (done % 10).zero?
        end

        # Flush remaining
        if @_batch && @_batch.any?
          embedded += flush_batch!(@_batch)
          @_batch = nil
        end

        warn "\r  done: #{done}/#{total} #{klass.name} records (#{embedded} embedded, #{done - embedded} unchanged)"
      end
    end

    # Batch: pre-fetch hashes, batch-embed changed texts, batch-write to DB
    def self.flush_batch!(batch)
      db = Database.connection

      # 1. Pre-fetch existing hashes in one query
      ids = batch.map { |b| b[:record_id] }
      record_type = batch.first[:record_type]
      placeholders = ids.map { "?" }.join(", ")
      existing = db.execute(
        "SELECT record_id, text_hash FROM ferret_documents WHERE record_type = ? AND record_id IN (#{placeholders})",
        [record_type] + ids
      ).to_h { |r| [r["record_id"], r["text_hash"]] }

      # 2. Filter to only changed records
      changed = batch.filter_map do |b|
        text_hash = Digest::SHA256.hexdigest(b[:clean_text])
        next if existing[b[:record_id]] == text_hash

        b.merge(text_hash: text_hash)
      end

      return 0 if changed.empty?

      # 3. Batch embed (single ONNX call for all changed texts)
      texts = changed.map { |b| b[:clean_text] }
      embeddings = embed_model.(texts)
      # embed_model returns a flat array for single input, nested for batch
      embeddings = [embeddings] if texts.length == 1 && !embeddings.first.is_a?(Array)

      # 4. Batch write in one transaction under one write lock
      Database.with_write_lock do
        db.transaction do
          changed.each_with_index do |b, i|
            blob = embeddings[i].pack("e*")

            db.execute(<<~SQL, [b[:record_type], b[:record_id], b[:clean_text], b[:text_hash]])
              INSERT INTO ferret_documents (record_type, record_id, searchable_text, text_hash, updated_at)
              VALUES (?, ?, ?, ?, datetime('now'))
              ON CONFLICT(record_type, record_id) DO UPDATE SET
                searchable_text = excluded.searchable_text,
                text_hash = excluded.text_hash,
                updated_at = datetime('now')
            SQL

            db.execute(<<~SQL, [b[:record_type], b[:record_id]])
              INSERT OR IGNORE INTO vec_lookup (record_type, record_id) VALUES (?, ?)
            SQL
            rowid = db.execute(
              "SELECT rowid FROM vec_lookup WHERE record_type = ? AND record_id = ?",
              [b[:record_type], b[:record_id]]
            ).first["rowid"]

            db.execute("DELETE FROM vec_documents WHERE rowid = ?", [rowid])
            db.execute("INSERT INTO vec_documents (rowid, embedding) VALUES (?, ?)", [rowid, blob])

            db.execute("DELETE FROM fts_documents WHERE record_type = ? AND record_id = ?", [b[:record_type], b[:record_id]])
            db.execute(
              "INSERT INTO fts_documents (rowid, record_type, record_id, searchable_text) VALUES (?, ?, ?, ?)",
              [rowid, b[:record_type], b[:record_id], b[:clean_text]]
            )
          end
        end
      end

      changed.length
    end

    def self.remove_record(record_type, record_id)
      db = Database.connection
      record_id = record_id.to_s

      Database.with_write_lock do
        lookup = db.execute(
          "SELECT rowid FROM vec_lookup WHERE record_type = ? AND record_id = ?",
          [record_type, record_id]
        ).first

        db.transaction do
          if lookup
            db.execute("DELETE FROM vec_documents WHERE rowid = ?", [lookup["rowid"]])
            db.execute("DELETE FROM fts_documents WHERE rowid = ?", [lookup["rowid"]])
            db.execute("DELETE FROM vec_lookup WHERE rowid = ?", [lookup["rowid"]])
          end
          db.execute(
            "DELETE FROM ferret_documents WHERE record_type = ? AND record_id = ?",
            [record_type, record_id]
          )
        end
      end
    end
  end
end
