# frozen_string_literal: true

require "ferret/version"
require "ferret/configuration"
require "ferret/database"
require "ferret/indexer"
require "ferret/searcher"
require "ferret/searchable"
require "ferret/jobs/embed_record_job"
require "ferret/railtie" if defined?(Rails::Railtie)

module Ferret
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def registry
      @registry ||= {}
    end

    def embed_all!(model_class = nil)
      Indexer.embed_all!(model_class)
    end

    def rebuild!
      Database.with_write_lock do
        db = Database.connection
        db.execute("DROP TABLE IF EXISTS vec_documents")
        db.execute("DROP TABLE IF EXISTS fts_documents")
        db.execute("DELETE FROM vec_lookup")
        db.execute("DELETE FROM ferret_documents")
        Database.migrate(db)
      end
      embed_all!
    end

    def status
      db = Database.connection
      registry.each_with_object({}) do |(klass, _fields), result|
        total = klass.count
        indexed = db.execute(
          "SELECT COUNT(*) as c FROM ferret_documents WHERE record_type = ?",
          [klass.name]
        ).first["c"]
        result[klass.name] = { total: total, indexed: indexed }
      end
    end
  end
end
