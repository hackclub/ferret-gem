# Ferret

Vector search + cross-encoder reranking for ActiveRecord, backed by a sidecar SQLite database.

Ferret adds semantic search to any ActiveRecord model with a single line of code. It runs entirely locally — no external APIs or services needed. Your primary database is never touched; all search data lives in a separate SQLite file.

## How it works

1. **Embed** — records are embedded with [all-mpnet-base-v2](https://huggingface.co/sentence-transformers/all-mpnet-base-v2) via ONNX (the [informers](https://github.com/ankane/informers) gem)
2. **Vector KNN** — query embedding is compared against stored embeddings using [sqlite-vec](https://github.com/asg017/sqlite-vec)
3. **Full-text search** — SQLite FTS5 with porter stemming provides keyword matching
4. **RRF fusion** — vector and FTS results are merged via Reciprocal Rank Fusion (vector weight 2.0, FTS weight 1.0, k=60)
5. **Cross-encoder rerank** — top candidates are rescored with [ms-marco-MiniLM-L-6-v2](https://huggingface.co/cross-encoder/ms-marco-MiniLM-L-6-v2) for high-precision final ranking

## Installation

Add to your Gemfile:

```ruby
gem "ferret", github: "hackclub/ferret-gem"
```

Run the install generator:

```bash
bin/rails g ferret:install
```

This creates `config/initializers/ferret.rb` and adds the sidecar DB to `.gitignore`.

## Usage

### Add to a model

```ruby
class Project < ApplicationRecord
  has_ferret_search :title, :description
end
```

This registers the model for indexing and adds an `after_commit` callback that enqueues a background job to embed the record whenever the relevent fields are created, updated, or destroyed.

### Search

```ruby
Project.ferret_search("game engine", limit: 10)
# => [#<Project id: 42, title: "3D Game Engine">, ...]

# Skip reranking for faster (but less precise) results
Project.ferret_search("game engine", rerank: false)
```

### Bulk embed

First-time setup or after adding `has_ferret_search` to a model:

```ruby
Ferret.embed_all!              # all registered models
Ferret.embed_all!(Project)     # just one model
```
```bash
bin/rails ferret:embed_all
```

`embed_all!` is idempotent — it hashes each record's searchable text and skips anything that hasn't changed. This makes it safe to call on every deploy or container start as a warmup step without re-embedding your entire dataset.

### Rebuild indexes

Drop all search data and re-embed from scratch:

```ruby
Ferret.rebuild!
```

```bash
bin/rails ferret:rebuild
```

### Check status

```ruby
Ferret.status
# => { "Project" => { total: 500, indexed: 480 }, "ShopItem" => { total: 120, indexed: 120 } }
```

```bash
bin/rails ferret:status
```

## Configuration

```ruby
# config/initializers/ferret.rb
Ferret.configure do |config|
  # Path to the sidecar SQLite database (default: db/ferret.sqlite3)
  config.database_path = Rails.root.join("db/ferret.sqlite3")

  # Embedding model (runs locally via ONNX, no API keys needed)
  config.embedding_model = "sentence-transformers/all-mpnet-base-v2"

  # Cross-encoder reranker model
  config.reranker_model = "cross-encoder/ms-marco-MiniLM-L-6-v2"

  # ActiveJob queue for background embedding
  config.queue = :default

  # Auto-embed records on save (set false to only embed via Ferret.embed_all!)
  config.embed_on_save = true

  # Enable cross-encoder reranking (slower but more accurate)
  config.rerank = true

  # Number of candidates to rerank
  config.rerank_pool = 37

  # Minimum rerank score (results below this are dropped)
  config.rerank_floor = 0.01

  # RRF fusion weights
  config.vec_weight = 2.0    # vector search weight
  config.fts_weight = 1.0    # full-text search weight
  config.rrf_k = 60.0        # RRF constant
end
```

## Dependencies

- **sqlite3** (~> 2.0) — SQLite database driver
- **sqlite-vec** (~> 0.1.7.alpha.10) — vector similarity search extension
- **informers** — ONNX model inference for embeddings and reranking
- **activerecord** (>= 7.0) — AR integration
- **activejob** (>= 7.0) — background embedding jobs

