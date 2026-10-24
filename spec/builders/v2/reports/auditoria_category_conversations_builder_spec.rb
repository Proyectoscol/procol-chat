require 'rails_helper'

RSpec.describe V2::Reports::AuditoriaCategoryConversationsBuilder do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  describe '#build with a term filter' do
    let(:category) { account.auditoria_categories.create!(title: 'Precio', match_type: :keyword, search_terms: "precio\nCX-5") }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:precio_message) { create(:message, account: account, inbox: inbox, conversation: conversation, content: 'me gusta el precio') }
    let!(:cx5_message) { create(:message, account: account, inbox: inbox, conversation: conversation, content: 'prefiero la CX-5') }

    before do
      Auditoria::CategoryMention.create!(account: account, category: category, conversation: conversation,
                                         message: precio_message, occurred_on: Date.current)
      Auditoria::CategoryMention.create!(account: account, category: category, conversation: conversation,
                                         message: cx5_message, occurred_on: Date.current)
    end

    it 'only reports the match reason for the filtered term, not every term that matched the conversation' do
      builder = described_class.new(account: account, params: { category_id: category.id, term: 'precio' })

      row = builder.build[:payload].first
      expect(row[:match_reasons]).to eq(['precio'])
    end

    it 'opens the representative message that actually contains the filtered term' do
      builder = described_class.new(account: account, params: { category_id: category.id, term: 'precio' })

      row = builder.build[:payload].first
      expect(row[:conversation][:id]).to eq(conversation.id)
      expect(row[:message][:id]).to eq(precio_message.id)
    end
  end

  describe '#build with a parent category and inbox-scoped visibility' do
    let(:other_inbox) { create(:inbox, account: account, name: 'Other inbox') }
    let(:parent) { account.auditoria_categories.create!(title: 'Competencia', match_type: :keyword, search_terms: 'x') }
    let!(:visible_child) do
      account.auditoria_categories.create!(title: 'Kia', match_type: :keyword, search_terms: 'kia', parent: parent, inbox_ids: [inbox.id])
    end
    let!(:hidden_child) do
      account.auditoria_categories.create!(title: 'Toyota', match_type: :keyword, search_terms: 'toyota', parent: parent, inbox_ids: [other_inbox.id])
    end

    it 'excludes a subcategory outside of the requested inbox scope from the drilldown' do
      visible_conversation = create(:conversation, account: account, inbox: inbox)
      Auditoria::CategoryMention.create!(account: account, category: visible_child, conversation: visible_conversation,
                                         occurred_on: Date.current)
      hidden_conversation = create(:conversation, account: account, inbox: other_inbox)
      Auditoria::CategoryMention.create!(account: account, category: hidden_child, conversation: hidden_conversation,
                                         occurred_on: Date.current)

      builder = described_class.new(account: account, params: { category_id: parent.id, inbox_id: inbox.id })

      ids = builder.build[:payload].map { |row| row[:conversation][:id] }
      expect(ids).to contain_exactly(visible_conversation.id)
    end
  end
end
