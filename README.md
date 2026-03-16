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
gem "ferret", path: "../ferret"  # or github: "hackclub/ferret"
gem "sqlite-vec"                  # see platform notes below
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

This registers the model for indexing and adds an `after_commit` callback that enqueues a background job to embed the record whenever it's created or updated.

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

Or via rake:

```bash
bin/rails ferret:embed_all
```

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

## sqlite-vec platform issues

The `sqlite-vec` gem has a platform naming problem: it publishes gems under `arm64-linux`, but Docker containers running on Apple Silicon (and other aarch64 systems) report their platform as `aarch64-linux`. Bundler can't resolve this mismatch.

Because of this, `sqlite-vec` is **not** declared as a dependency in the ferret gemspec. You need to handle it yourself.

### On macOS (native)

No issues — just add `gem "sqlite-vec"` to your Gemfile and it works.

### In Docker (aarch64-linux)

The `arm64-linux` gem installs but ships a **32-bit ARM binary** that won't load on 64-bit aarch64. You need to compile sqlite-vec from source.

Add this to your Dockerfile:

```dockerfile
# Compile sqlite-vec from source for aarch64
RUN apt-get update && apt-get install -y wget gettext-base && \
    cd /tmp && \
    wget -q https://github.com/asg017/sqlite-vec/archive/refs/tags/v0.1.6.tar.gz && \
    tar xzf v0.1.6.tar.gz && \
    cd sqlite-vec-0.1.6 && \
    make loadable && \
    cp dist/vec0.so /tmp/vec0.so && \
    cd / && rm -rf /tmp/sqlite-vec-0.1.6 /tmp/v0.1.6.tar.gz
```

Then after `gem install sqlite-vec`, replace the shipped `.so` with your compiled one:

```dockerfile
RUN gem install sqlite-vec && \
    VEC_DIR=$(find /usr/local/bundle/gems -name "sqlite-vec-*" -type d | head -1) && \
    cp /tmp/vec0.so "$VEC_DIR/lib/vec0.so"
```

You may also need to do this at container startup if bundler reinstalls gems (e.g. in a dev entrypoint script).

### Future fix: sqlite-vec 0.1.7

This is a known upstream issue: [asg017/sqlite-vec#148](https://github.com/asg017/sqlite-vec/issues/148). The maintainer has published `v0.1.7-alpha.2` with a proper aarch64 fix (confirmed working by multiple users), but the Ruby gem hasn't been updated yet — only the NPM package got the alpha. Once `sqlite-vec` gem `0.1.7` is released:

1. Update the Dockerfile to install `sqlite-vec 0.1.7` normally (drop the compile-from-source step)
2. Add `sqlite-vec` back as a gemspec dependency in ferret
3. Remove the `LoadError` rescue fallback in `database.rb`

### Why not just fix the gem dependency today?

Ferret uses a `LoadError` rescue fallback that manually adds sqlite-vec's gem path to `$LOAD_PATH` when bundler blocks the require. This lets it work even when bundler doesn't recognize the gem as properly installed. It's not pretty, but it's reliable.

## Dependencies

- **sqlite3** (~> 2.0) — SQLite database driver
- **informers** — ONNX model inference for embeddings and reranking
- **activerecord** (>= 7.0) — AR integration
- **activejob** (>= 7.0) — background embedding jobs
- **sqlite-vec** (runtime, not in gemspec) — vector similarity search extension

