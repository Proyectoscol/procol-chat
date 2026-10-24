require 'rails_helper'

RSpec.describe Auditoria::Category do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  let(:parent) { account.auditoria_categories.create!(title: 'Parent', match_type: :keyword, search_terms: 'x') }

  it 'is valid with the minimal required attributes' do
    category = account.auditoria_categories.new(title: 'Billing', match_type: :keyword, search_terms: 'invoice')

    expect(category).to be_valid
  end

  it 'rejects a parent that belongs to a different account' do
    foreign_parent = other_account.auditoria_categories.create!(title: 'Foreign', match_type: :keyword, search_terms: 'x')
    category = account.auditoria_categories.new(title: 'Child', match_type: :keyword, search_terms: 'y', parent: foreign_parent)

    expect(category).not_to be_valid
    expect(category.errors[:parent]).to be_present
  end

  it 'rejects a 3-level hierarchy (a child of a child)' do
    child = account.auditoria_categories.create!(title: 'Child', match_type: :keyword, search_terms: 'a', parent: parent)
    grandchild = account.auditoria_categories.new(title: 'Grandchild', match_type: :keyword, search_terms: 'b', parent: child)

    expect(grandchild).not_to be_valid
    expect(grandchild.errors[:parent]).to be_present
  end

  it 'rejects promoting a category that already has children into being itself a child' do
    child = account.auditoria_categories.create!(title: 'Child', match_type: :keyword, search_terms: 'a', parent: parent)
    other_top_level = account.auditoria_categories.create!(title: 'Other', match_type: :keyword, search_terms: 'z')

    parent.parent = other_top_level

    expect(parent).not_to be_valid
    expect(parent.errors[:parent]).to be_present
    expect(child.reload.parent_id).to eq(parent.id)
  end

  it 'rejects a category being its own parent' do
    category = account.auditoria_categories.create!(title: 'Self', match_type: :keyword, search_terms: 'a')
    category.parent_id = category.id

    expect(category).not_to be_valid
  end
end
