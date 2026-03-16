# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ferret::Searchable do
  describe ".has_ferret_search" do
    it "registers the model and fields in the Ferret registry" do
      expect(Ferret.registry[TestProject]).to eq(%i[title description])
    end

    it "adds a ferret_search class method" do
      expect(TestProject).to respond_to(:ferret_search)
    end

    it "adds ferret_index and ferret_remove instance methods" do
      project = TestProject.new(title: "Test", description: "A test project")
      expect(project).to respond_to(:ferret_index)
      expect(project).to respond_to(:ferret_remove)
    end
  end
end
