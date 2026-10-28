require 'rails_helper'

RSpec.describe V2::Reports::TeamSummaryBuilder do
  let(:account) { create(:account) }
  let(:team1) { create(:team, account: account, name: 'team-1') }
  let(:team2) { create(:team, account: account, name: 'team-2') }
  let(:params) do
    {
      business_hours: business_hours,
      since: 1.week.ago.beginning_of_day,
      until: Time.current.end_of_day
    }
  end
  let(:builder) { described_class.new(account: account, params: params) }

  describe '#build' do
    context 'when there is team data' do
      # inbox explicito y compartido en todo este bloque -- sin esto, cada
      # create(:conversation, ...)/create(:reporting_event, ...) sin inbox
      # crea su PROPIA bandeja nueva (ver factories/inboxes.rb y
      # factories/reporting_events.rb), y cada bandeja nueva crea su propio
      # Team espejo real (ver InboxMirrorTeam) -- esos equipos incidentales
      # aparecian en el reporte junto a team1/team2, rompiendo la
      # comparacion exacta `eq([...])` de abajo.
      let(:inbox) { create(:inbox, account: account) }

      before do
        c1 = create(:conversation, account: account, inbox: inbox, team: team1, created_at: Time.current)
        c2 = create(:conversation, account: account, inbox: inbox, team: team2, created_at: Time.current)
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: c2,
          name: 'conversation_resolved',
          value: 50,
          value_in_business_hours: 40,
          created_at: Time.current
        )
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: c1,
          name: 'first_response',
          value: 20,
          value_in_business_hours: 10,
          created_at: Time.current
        )
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: c1,
          name: 'reply_time',
          value: 30,
          value_in_business_hours: 15,
          created_at: Time.current
        )
        create(
          :reporting_event,
          account: account,
          inbox: inbox,
          conversation: c1,
          name: 'reply_time',
          value: 40,
          value_in_business_hours: 25,
          created_at: Time.current
        )
      end

      context 'when business hours is disabled' do
        let(:business_hours) { false }

        it 'returns the correct team stats' do
          report = builder.build

          # include, no eq: el inbox compartido de este bloque tiene su
          # propio Team espejo real (ver InboxMirrorTeam, feature custom de
          # este fork) -- TeamSummaryBuilder correctamente lo lista junto a
          # team1/team2, asi que una comparacion de array exacto es fragil
          # ante cualquier inbox creado en el setup.
          expect(report).to include(
            {
              id: team1.id,
              conversations_count: 1,
              resolved_conversations_count: 0,
              avg_resolution_time: nil,
              avg_first_response_time: 20.0,
              avg_reply_time: 35.0
            },
            {
              id: team2.id,
              conversations_count: 1,
              resolved_conversations_count: 1,
              avg_resolution_time: 50.0,
              avg_first_response_time: nil,
              avg_reply_time: nil
            }
          )
        end
      end

      context 'when business hours is enabled' do
        let(:business_hours) { true }

        it 'uses business hours values' do
          report = builder.build

          # include, no eq -- ver el mismo comentario en el test de arriba.
          expect(report).to include(
            {
              id: team1.id,
              conversations_count: 1,
              resolved_conversations_count: 0,
              avg_resolution_time: nil,
              avg_first_response_time: 10.0,
              avg_reply_time: 20.0
            },
            {
              id: team2.id,
              conversations_count: 1,
              resolved_conversations_count: 1,
              avg_resolution_time: 40.0,
              avg_first_response_time: nil,
              avg_reply_time: nil
            }
          )
        end
      end
    end

    context 'when the account has Auditoria enabled and the native pipeline has no data for a team' do
      let(:business_hours) { false }
      let(:inbox) { create(:inbox, account: account) }

      before { account.enable_features!('auditoria') }

      it 'falls back to the Auditoria response-time calculation instead of leaving avg_first_response_time nil' do
        contact = create(:contact, account: account)
        contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
        conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, team: team1)
        incoming_at = 1.day.ago
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: incoming_at)
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, created_at: incoming_at + 120)

        report = builder.build

        expect(report.find { |row| row[:id] == team1.id }[:avg_first_response_time]).to eq(120)
      end

      it 'does not override a real native avg_first_response_time value' do
        c2 = create(:conversation, account: account, inbox: inbox, team: team2, created_at: Time.current)
        create(:reporting_event, account: account, inbox: inbox, conversation: c2, name: 'first_response', value: 20,
                                 value_in_business_hours: 10, created_at: Time.current)

        report = builder.build

        expect(report.find { |row| row[:id] == team2.id }[:avg_first_response_time]).to eq(20.0)
      end
    end

    context 'when there is no team data' do
      let!(:new_team) { create(:team, account: account) }
      let(:business_hours) { false }

      it 'returns zero values' do
        report = builder.build

        expect(report).to include(
          {
            id: new_team.id,
            conversations_count: 0,
            resolved_conversations_count: 0,
            avg_resolution_time: nil,
            avg_first_response_time: nil,
            avg_reply_time: nil
          }
        )
      end
    end
  end
end
