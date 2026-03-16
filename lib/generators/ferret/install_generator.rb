# frozen_string_literal: true

module Ferret
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc "Creates a Ferret initializer"

      def add_gitignore
        append_to_file ".gitignore", "\n# Ferret vector search sidecar database\n/db/ferret.sqlite3*\n"
      end

      def create_initializer
        create_file "config/initializers/ferret.rb", <<~RUBY
          # frozen_string_literal: true

          Ferret.configure do |config|
            # Path to the sidecar SQLite database (no changes to your primary DB)
            # config.database_path = Rails.root.join("db/ferret.sqlite3")

            # Embedding model (runs locally via ONNX, no API keys needed)
            # config.embedding_model = "sentence-transformers/all-mpnet-base-v2"

            # Cross-encoder reranker model
            # config.reranker_model = "cross-encoder/ms-marco-MiniLM-L-6-v2"

            # ActiveJob queue for background embedding
            # config.queue = :default

            # Auto-embed records on save (set false to only embed via Ferret.embed_all!)
            # config.embed_on_save = true

            # Enable cross-encoder reranking (slower but more accurate)
            # config.rerank = true
          end
        RUBY
      end
    end
  end
end
