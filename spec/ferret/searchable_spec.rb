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

  describe "after_commit lifecycle" do
    before do
      allow(Ferret.configuration).to receive(:embed_on_save).and_return(true)
    end

    it "detects ferret field changes on create" do
      project = TestProject.create!(title: "New", description: "Project")
      expect(project.saved_changes_to_ferret_fields?).to be true
    end

    it "detects ferret field changes on update" do
      project = TestProject.create!(title: "Old", description: "Project")
      project.update!(title: "Updated")
      expect(project.saved_changes_to_ferret_fields?).to be true
    end

    it "ignores non-ferret field changes on update" do
      project = TestProject.create!(title: "Same", description: "Project")
      project.update!(updated_at: Time.now)
      expect(project.saved_changes_to_ferret_fields?).to be false
    end
  end
end
