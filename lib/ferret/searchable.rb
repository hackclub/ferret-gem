# frozen_string_literal: true

require "active_support/concern"

module Ferret
  module Searchable
    extend ActiveSupport::Concern

    class_methods do
      def has_ferret_search(*fields)
        Ferret.registry[self] = fields.map(&:to_sym)

        after_commit :ferret_index, on: %i[create update], if: -> { Ferret.configuration.embed_on_save }
        after_commit :ferret_remove, on: :destroy

        define_method(:ferret_index) do
          if defined?(Ferret::EmbedRecordJob)
            Ferret::EmbedRecordJob.perform_later(self.class.name, id)
          else
            Ferret::Indexer.index_record(self)
          end
        end

        define_method(:ferret_remove) do
          Ferret::Indexer.remove_record(self.class.name, id.to_s)
        end
      end

      def ferret_search(query, limit: 20, rerank: nil)
        Ferret::Searcher.search(self, query, limit: limit, rerank: rerank)
      end
    end
  end
end
