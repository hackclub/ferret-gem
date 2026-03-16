# frozen_string_literal: true

module Ferret
  class EmbedRecordJob < ActiveJob::Base
    queue_as { Ferret.configuration.queue }

    def perform(record_type, record_id)
      klass = record_type.constantize
      record = klass.find_by(id: record_id)
      return unless record

      Ferret::Indexer.index_record(record)
    end
  end
end
