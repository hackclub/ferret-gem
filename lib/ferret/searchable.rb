# frozen_string_literal: true

require "active_support/concern"
require "set"

module Ferret
  module Searchable
    extend ActiveSupport::Concern

    class_methods do
      # has_ferret_search :title, :description
      # has_ferret_search :name, :description, type: -> { type.demodulize.underscore.humanize }
      #
      # Positional args are columns — tracked for changes and called for text.
      # Keyword args map a column (for change tracking) to a lambda (for text).
      def has_ferret_search(*fields, **mapped_fields)
        text_sources = [*fields.map(&:to_sym), *mapped_fields.values].freeze
        watch_columns = [*fields.map(&:to_sym), *mapped_fields.keys.map(&:to_sym)].to_set.freeze

        Ferret.registry[self] = text_sources

        ferret_base_name = name

        after_commit :ferret_index,
                     on: %i[create update],
                     if: -> { Ferret.configuration.embed_on_save && saved_changes_to_ferret_fields? }
        after_commit :ferret_remove, on: :destroy

        define_method(:saved_changes_to_ferret_fields?) do
          !persisted_before_last_save || saved_changes.keys.any? { |k| watch_columns.include?(k.to_sym) }
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
