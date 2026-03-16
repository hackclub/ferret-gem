# frozen_string_literal: true

module Ferret
  class Railtie < Rails::Railtie
    initializer "ferret.set_defaults" do
      Ferret.configuration.database_path ||= Rails.root.join("db", "ferret.sqlite3")
    end

    initializer "ferret.extend_active_record" do
      ActiveSupport.on_load(:active_record) do
        include Ferret::Searchable
      end
    end

    rake_tasks do
      namespace :ferret do
        desc "Embed all registered models"
        task embed_all: :environment do
          Ferret.embed_all!
        end

        desc "Rebuild ferret indexes from scratch"
        task rebuild: :environment do
          Ferret.rebuild!
        end

        desc "Show ferret indexing status"
        task status: :environment do
          Ferret.status.each do |model, counts|
            puts "#{model}: #{counts[:indexed]}/#{counts[:total]} indexed"
          end
        end
      end
    end
  end
end
