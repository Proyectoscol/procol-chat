require 'rails_helper'

RSpec.describe V2::Reports::AuditoriaSentimentTimeseriesBuilder do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let(:since) { 10.days.ago.beginning_of_day.to_i }
  let(:until_) { Time.current.end_of_day.to_i }
  let(:params) { { since: since, until: until_ } }
  let(:builder) { described_class.new(account: account, params: params) }

  def analysis_for(sentiment:, created_at:, labels: [], source_user: nil, conversation_inbox: inbox)
    conversation = create(:conversation, account: account, inbox: conversation_inbox, created_at: created_at)
    conversation.update_labels(*labels) if labels.any?
    if source_user
      create(:message, account: account, inbox: conversation_inbox, conversation: conversation,
                       message_type: 'outgoing', content_attributes: { 'auditoria_source_user_id' => source_user.id })
    end
    create(:auditoria_conversation_analysis, account: account, conversation: conversation, sentiment: sentiment)
    conversation
  end

  def points_for(sentiment)
    builder.build[:series].find { |s| s[:sentiment] == sentiment }[:points]
  end

  def count_on(sentiment, date)
    points_for(sentiment).find { |p| p[:date] == date.to_s }&.fetch(:count) || 0
  end

  describe '#build' do
    it 'groups conversations by sentiment and the day they started' do
      analysis_for(sentiment: 'positive', created_at: 2.days.ago.noon)
      analysis_for(sentiment: 'positive', created_at: 2.days.ago.noon)
      analysis_for(sentiment: 'negative', created_at: 2.days.ago.noon)

      expect(count_on('positive', 2.days.ago.to_date)).to eq(2)
      expect(count_on('negative', 2.days.ago.to_date)).to eq(1)
      expect(count_on('neutral', 2.days.ago.to_date)).to eq(0)
    end

    it 'always returns the 3 fixed sentiment series, even with no data' do
      expect(builder.build[:series].map { |s| s[:sentiment] }).to contain_exactly('positive', 'neutral', 'negative')
    end

    # Regresion del bug corregido donde date_trunc truncaba el timestamp UTC
    # crudo sin convertir a la zona de la cuenta (America/Bogota, GMT-5) --
    # una conversacion creada a las 11pm hora Bogota cae en la madrugada del
    # dia siguiente en UTC, asi que sin la conversion el bucket quedaba un
    # dia adelante.
    it 'buckets a conversation created late at night in the account timezone on the correct calendar day' do
      reference_date = 2.days.ago.to_date
      late_night_bogota = ActiveSupport::TimeZone['America/Bogota'].local(
        reference_date.year, reference_date.month, reference_date.day, 23, 0, 0
      )
      analysis_for(sentiment: 'positive', created_at: late_night_bogota)

      expect(count_on('positive', reference_date)).to eq(1)
      expect(count_on('positive', reference_date + 1)).to eq(0)
    end

    it 'excludes conversations tagged as having multiple advisors' do
      analysis_for(sentiment: 'positive', created_at: 2.days.ago.noon,
                   labels: [Auditoria::MessageAnnotatorService::MULTIPLE_ADVISORS_LABEL_TITLE])

      expect(count_on('positive', 2.days.ago.to_date)).to eq(0)
    end

    it 'only counts conversations whose created_at is within the requested range' do
      analysis_for(sentiment: 'positive', created_at: 20.days.ago.noon)

      expect(builder.build[:series].sum { |s| s[:points].sum { |p| p[:count] } }).to eq(0)
    end

    context 'with inbox_id filter' do
      let!(:other_inbox) { create(:inbox, account: account, name: 'Other inbox') }
      let(:params) { { since: since, until: until_, inbox_id: inbox.id } }

      it 'only includes conversations from the given inbox' do
        analysis_for(sentiment: 'positive', created_at: 2.days.ago.noon, conversation_inbox: inbox)
        analysis_for(sentiment: 'positive', created_at: 2.days.ago.noon, conversation_inbox: other_inbox)

        expect(count_on('positive', 2.days.ago.to_date)).to eq(1)
      end
    end

    context 'with user_id filter' do
      let!(:advisor) { create(:user, account: account) }
      let!(:other_advisor) { create(:user, account: account) }
      let(:params) { { since: since, until: until_, user_id: advisor.id } }

      it 'only includes conversations attributed to that advisor' do
        analysis_for(sentiment: 'positive', created_at: 2.days.ago.noon, source_user: advisor)
        analysis_for(sentiment: 'positive', created_at: 2.days.ago.noon, source_user: other_advisor)

        expect(count_on('positive', 2.days.ago.to_date)).to eq(1)
      end
    end

    context 'with team_id filter' do
      let!(:team) { create(:team, account: account) }
      let!(:team_member) { create(:user, account: account) }
      let!(:non_member) { create(:user, account: account) }
      let(:params) { { since: since, until: until_, team_id: team.id } }

      before { create(:team_member, team: team, user: team_member) }

      it 'only includes conversations attributed to a member of that team' do
        analysis_for(sentiment: 'positive', created_at: 2.days.ago.noon, source_user: team_member)
        analysis_for(sentiment: 'positive', created_at: 2.days.ago.noon, source_user: non_member)

        expect(count_on('positive', 2.days.ago.to_date)).to eq(1)
      end
    end

    context 'when both user_id and team_id are given' do
      let!(:team) { create(:team, account: account) }
      let!(:advisor) { create(:user, account: account) }
      let!(:team_member) { create(:user, account: account) }
      let(:params) { { since: since, until: until_, user_id: advisor.id, team_id: team.id } }

      before { create(:team_member, team: team, user: team_member) }

      # El UI deja los dos selects mutuamente excluyentes (ver
      # AuditoriaSentimentReportsIndex.vue#onAdvisorChange/onTeamChange), asi
      # que esto solo documenta la regla de precedencia real del backend si
      # algo mandara ambos de todas formas.
      it 'gives priority to user_id and ignores team_id' do
        analysis_for(sentiment: 'positive', created_at: 2.days.ago.noon, source_user: advisor)
        analysis_for(sentiment: 'positive', created_at: 2.days.ago.noon, source_user: team_member)

        expect(count_on('positive', 2.days.ago.to_date)).to eq(1)
      end
    end
  end
end
