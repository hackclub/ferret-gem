# frozen_string_literal: true

module Ferret
  module Database
    EMBED_DIM = 768 # all-mpnet-base-v2

    @mutex = Mutex.new
    @write_mutex = Mutex.new

    def self.connection
      @db || @mutex.synchronize do
        @db ||= begin
          require "sqlite3"
          # Load sqlite-vec, handling the case where bundler restricts it
          # (sqlite-vec has a platform naming issue: publishes arm64-linux
          # but aarch64-linux Docker containers can't resolve it through bundler)
          begin
            require "sqlite_vec"
          rescue LoadError
            # Try loading from gem install path directly
            vec_paths = Gem.path.flat_map { |p| Dir.glob("#{p}/gems/sqlite-vec-*/lib") }
            vec_paths.each { |p| $LOAD_PATH.unshift(p) unless $LOAD_PATH.include?(p) }
            require "sqlite_vec"
          end
          path = Ferret.configuration.database_path
          FileUtils.mkdir_p(File.dirname(path))
          db = SQLite3::Database.new(path.to_s)
          db.results_as_hash = true
          db.execute("PRAGMA journal_mode=WAL")
          db.execute("PRAGMA synchronous=NORMAL")
          db.execute("PRAGMA busy_timeout=5000")
          db.enable_load_extension(true)
          SqliteVec.load(db)
          db.enable_load_extension(false)
          migrate(db)
          db
        end
      end
    end

    # Serialize write operations to avoid SQLite "database is locked" errors
    def self.with_write_lock(&block)
      @write_mutex.synchronize(&block)
    end

    def self.reset_connection!
      @mutex.synchronize do
        @db&.close rescue nil
        @db = nil
      end
    end

    def self.migrate(db)
      db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS ferret_documents (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          record_type TEXT NOT NULL,
          record_id TEXT NOT NULL,
          searchable_text TEXT,
          text_hash TEXT,
          updated_at TEXT DEFAULT (datetime('now')),
          UNIQUE(record_type, record_id)
        )
      SQL

      db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS vec_lookup (
          rowid INTEGER PRIMARY KEY AUTOINCREMENT,
          record_type TEXT NOT NULL,
          record_id TEXT NOT NULL,
          UNIQUE(record_type, record_id)
        )
      SQL

      db.execute(<<~SQL)
        CREATE VIRTUAL TABLE IF NOT EXISTS vec_documents USING vec0(
          rowid INTEGER PRIMARY KEY,
          embedding float[#{EMBED_DIM}]
        )
      SQL

      db.execute(<<~SQL)
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_documents USING fts5(
          record_type UNINDEXED,
          record_id UNINDEXED,
          searchable_text,
          content='',
          tokenize='porter unicode61'
        )
      SQL
    end

    def self.clean(text)
      return nil if text.nil?
      text = text.gsub(/https?:\/\/\S+/, "")
      text = text.gsub(/[#*_`~\[\]()>|]/, "")
      text = text.gsub(/\s+/, " ").strip
      text
    end
  end
end
