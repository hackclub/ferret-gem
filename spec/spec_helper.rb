# frozen_string_literal: true

require "active_record"
require "active_job"
require "ferret"
require "tmpdir"

# Set up an in-memory ActiveRecord database for testing
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  create_table :test_projects, force: true do |t|
    t.string :title
    t.text :description
    t.timestamps
  end
end

# Test model — defined once, reused across specs
class TestProject < ActiveRecord::Base
  include Ferret::Searchable
  has_ferret_search :title, :description
end

# Configure ferret to use a temp database for tests
FERRET_TEST_DB = File.join(Dir.tmpdir, "ferret_test_#{Process.pid}.sqlite3")

Ferret.configure do |config|
  config.database_path = FERRET_TEST_DB
  config.embed_on_save = false
end

RSpec.configure do |config|
  config.after(:suite) do
    Ferret::Database.reset_connection!
    File.delete(FERRET_TEST_DB) if File.exist?(FERRET_TEST_DB)
    Dir.glob("#{FERRET_TEST_DB}-*").each { |f| File.delete(f) }
  end
end
