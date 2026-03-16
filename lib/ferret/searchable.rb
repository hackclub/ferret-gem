# frozen_string_literal: true

require "active_support/concern"

module Ferret
  module Searchable
    extend ActiveSupport::Concern

    class_methods do
      def has_ferret_search(*fields)
        require "set"
        ferret_fields = fields.map(&:to_sym).to_set.freeze
        Ferret.registry[self] = ferret_fields

        # Store the base class name for STI support — subclasses should
        # all index under the parent class that called has_ferret_search.
        ferret_base_name = name

        after_commit :ferret_index, on: %i[create update],
                     if: -> { Ferret.configuration.embed_on_save && saved_changes_to_ferret_fields? }
        after_commit :ferret_remove, on: :destroy

        define_method(:saved_changes_to_ferret_fields?) do
          # Always index on create; on update, only if a searchable field changed
          !persisted_before_last_save || saved_changes.keys.any? { |k| ferret_fields.include?(k.to_sym) }
        end

        define_method(:ferret_index) do
          if defined?(Ferret::EmbedRecordJob)
            Ferret::EmbedRecordJob.perform_later(ferret_base_name, id)
          else
            Ferret::Indexer.index_record(self)
          end
        end

        define_method(:ferret_remove) do
          Ferret::Indexer.remove_record(ferret_base_name, id.to_s)
        end
      end

      def ferret_search(query, limit: 20, rerank: nil)
        Ferret::Searcher.search(self, query, limit: limit, rerank: rerank)
      end
    end
  end
end
