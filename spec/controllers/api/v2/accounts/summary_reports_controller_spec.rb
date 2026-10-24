require 'rails_helper'

RSpec.describe 'Summary Reports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:default_timezone) { ActiveSupport::TimeZone[0]&.name }
  let(:start_of_today) { Time.current.in_time_zone(default_timezone).beginning_of_day.to_i }
  let(:end_of_today) { Time.current.in_time_zone(default_timezone).end_of_day.to_i }

  describe 'GET /api/v2/accounts/:account_id/summary_reports/agent' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/summary_reports/agent"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:params) do
        {
          since: start_of_today.to_s,
          until: end_of_today.to_s,
          business_hours: true
        }
      end

      it 'returns unauthorized for agents' do
        get "/api/v2/accounts/#{account.id}/summary_reports/agent",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'calls V2::Reports::AgentSummaryBuilder with the right params if the user is an admin' do
        agent_summary_builder = double
        allow(V2::Reports::AgentSummaryBuilder).to receive(:new).and_return(agent_summary_builder)
        allow(agent_summary_builder).to receive(:build).and_return([{ id: 1, conversations_count: 110 }])

        get "/api/v2/accounts/#{account.id}/summary_reports/agent",
            params: params,
            headers: admin.create_new_auth_token,
            as: :json

        expect(V2::Reports::AgentSummaryBuilder).to have_received(:new).with(
          account: account,
          params: params.merge(type: :agent)
        )
        expect(agent_summary_builder).to have_received(:build)

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        expect(json_response.length).to eq(1)
        expect(json_response.first['id']).to eq(1)
        expect(json_response.first['conversations_count']).to eq(110)
        expect(json_response.first['avg_reply_time']).to be_nil
      end
    end
  end

  describe 'GET /api/v2/accounts/:account_id/summary_reports/inbox' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/summary_reports/inbox"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:params) do
        {
          since: start_of_today.to_s,
          until: end_of_today.to_s,
          business_hours: true
        }
      end

      it 'returns unauthorized for inbox' do
        get "/api/v2/accounts/#{account.id}/summary_reports/inbox",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'calls V2::Reports::InboxSummaryBuilder with the right params if the user is an admin' do
        inbox_summary_builder = double
        allow(V2::Reports::InboxSummaryBuilder).to receive(:new).and_return(inbox_summary_builder)
        allow(inbox_summary_builder).to receive(:build).and_return([{ id: 1, conversations_count: 110 }])

        get "/api/v2/accounts/#{account.id}/summary_reports/inbox",
            params: params,
            headers: admin.create_new_auth_token,
            as: :json

        expect(V2::Reports::InboxSummaryBuilder).to have_received(:new).with(
          account: account,
          params: params.merge(type: :inbox)
        )
        expect(inbox_summary_builder).to have_received(:build)

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        expect(json_response.length).to eq(1)
        expect(json_response.first['id']).to eq(1)
        expect(json_response.first['conversations_count']).to eq(110)
        expect(json_response.first['avg_reply_time']).to be_nil
      end
    end
  end

  describe 'GET /api/v2/accounts/:account_id/summary_reports/team' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/summary_reports/team"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:params) do
        {
          since: start_of_today.to_s,
          until: end_of_today.to_s,
          business_hours: true
        }
      end

      it 'returns unauthorized for agents' do
        get "/api/v2/accounts/#{account.id}/summary_reports/team",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'calls V2::Reports::TeamSummaryBuilder with the right params if the user is an admin' do
        team_summary_builder = double
        allow(V2::Reports::TeamSummaryBuilder).to receive(:new).and_return(team_summary_builder)
        allow(team_summary_builder).to receive(:build).and_return([{ id: 1, conversations_count: 110 }])

        get "/api/v2/accounts/#{account.id}/summary_reports/team",
            params: params,
            headers: admin.create_new_auth_token,
            as: :json

        expect(V2::Reports::TeamSummaryBuilder).to have_received(:new).with(
          account: account,
          params: params.merge(type: :team)
        )
        expect(team_summary_builder).to have_received(:build)

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        expect(json_response.length).to eq(1)
        expect(json_response.first['id']).to eq(1)
        expect(json_response.first['conversations_count']).to eq(110)
        expect(json_response.first['avg_reply_time']).to be_nil
      end
    end
  end

  describe 'GET /api/v2/accounts/:account_id/summary_reports/channel' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/summary_reports/channel"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:params) do
        {
          since: start_of_today.to_s,
          until: end_of_today.to_s
        }
      end

      it 'returns unauthorized for agents' do
        get "/api/v2/accounts/#{account.id}/summary_reports/channel",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'calls V2::Reports::ChannelSummaryBuilder with the right params if the user is an admin' do
        channel_summary_builder = double
        allow(V2::Reports::ChannelSummaryBuilder).to receive(:new).and_return(channel_summary_builder)
        allow(channel_summary_builder).to receive(:build)
          .and_return({
                        'Channel::WebWidget' => { open: 5, resolved: 10, pending: 2, snoozed: 1, total: 18 }
                      })

        get "/api/v2/accounts/#{account.id}/summary_reports/channel",
            params: params,
            headers: admin.create_new_auth_token,
            as: :json

        expect(V2::Reports::ChannelSummaryBuilder).to have_received(:new).with(
          account: account,
          params: hash_including(since: start_of_today.to_s, until: end_of_today.to_s)
        )
        expect(channel_summary_builder).to have_received(:build)

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body

        expect(json_response['Channel::WebWidget']['open']).to eq(5)
        expect(json_response['Channel::WebWidget']['total']).to eq(18)
      end

      it 'returns unprocessable_entity when date range exceeds 6 months' do
        get "/api/v2/accounts/#{account.id}/summary_reports/channel",
            params: { since: 1.year.ago.to_i.to_s, until: Time.current.to_i.to_s },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('errors.reports.date_range_too_long'))
      end
    end
  end

  describe 'GET /api/v2/accounts/:account_id/summary_reports/auditoria_sentiment_timeseries' do
    let(:params) { { since: start_of_today.to_s, until: end_of_today.to_s } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/summary_reports/auditoria_sentiment_timeseries"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/summary_reports/auditoria_sentiment_timeseries",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the auditoria feature is not enabled for the account' do
      it 'returns unauthorized even for an admin' do
        get "/api/v2/accounts/#{account.id}/summary_reports/auditoria_sentiment_timeseries",
            params: params,
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an admin with the auditoria feature enabled' do
      before { account.enable_features!('auditoria') }

      it 'calls the timeseries builder with the request params' do
        builder = double
        allow(V2::Reports::AuditoriaSentimentTimeseriesBuilder).to receive(:new).and_return(builder)
        allow(builder).to receive(:build).and_return({ bucket: 'day', series: [] })

        get "/api/v2/accounts/#{account.id}/summary_reports/auditoria_sentiment_timeseries",
            params: params,
            headers: admin.create_new_auth_token,
            as: :json

        expect(V2::Reports::AuditoriaSentimentTimeseriesBuilder).to have_received(:new).with(
          account: account,
          params: hash_including(since: start_of_today.to_s, until: end_of_today.to_s)
        )
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['bucket']).to eq('day')
      end

      context 'when the admin is restricted to specific inboxes' do
        let!(:allowed_inbox) { create(:inbox, account: account, name: 'Allowed inbox') }

        before do
          admin.account_users.find_by(account: account).update!(restricted_inbox_ids: [allowed_inbox.id])
        end

        it 'forces inbox_id to the restricted inboxes, ignoring any inbox_id sent by the client' do
          builder = double
          allow(V2::Reports::AuditoriaSentimentTimeseriesBuilder).to receive(:new).and_return(builder)
          allow(builder).to receive(:build).and_return({ bucket: 'day', series: [] })

          get "/api/v2/accounts/#{account.id}/summary_reports/auditoria_sentiment_timeseries",
              params: params.merge(inbox_id: 999_999),
              headers: admin.create_new_auth_token,
              as: :json

          expect(V2::Reports::AuditoriaSentimentTimeseriesBuilder).to have_received(:new).with(
            account: account,
            params: hash_including(inbox_id: [allowed_inbox.id])
          )
        end
      end
    end
  end

  describe 'GET /api/v2/accounts/:account_id/summary_reports/auditoria_sentiment_conversations' do
    let(:params) { { since: start_of_today.to_s, until: end_of_today.to_s, page: '1' } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/summary_reports/auditoria_sentiment_conversations"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/summary_reports/auditoria_sentiment_conversations",
            params: params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an admin with the auditoria feature enabled' do
      before { account.enable_features!('auditoria') }

      it 'calls the conversations builder with the request params' do
        builder = double
        allow(V2::Reports::AuditoriaSentimentConversationsBuilder).to receive(:new).and_return(builder)
        allow(builder).to receive(:build).and_return({ meta: { current_page: 1, per_page: 25, total_count: 0 }, payload: [] })

        get "/api/v2/accounts/#{account.id}/summary_reports/auditoria_sentiment_conversations",
            params: params.merge(sentiment: 'positive'),
            headers: admin.create_new_auth_token,
            as: :json

        expect(V2::Reports::AuditoriaSentimentConversationsBuilder).to have_received(:new).with(
          account: account,
          params: hash_including(since: start_of_today.to_s, until: end_of_today.to_s, sentiment: 'positive')
        )
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['meta']['total_count']).to eq(0)
      end
    end
  end
end
