# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sip::InternalController', type: :request do
  let(:account) { create(:account) }
  let(:events_path) { '/api/v1/internal/sip/events' }

  describe 'POST /api/v1/internal/sip/events' do
    # --- Authentication: exercises the REAL authenticate_sip_request! ----------
    # With no matching token, valid_token? returns false (blank header/ENV) → 401.
    # Deterministic without touching ENV, since both paths reject.
    it 'returns 401 when the token header is missing' do
      post events_path, params: { type: 'register', extension: '9001' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 when an invalid token is provided' do
      post events_path,
           params: { type: 'register', extension: '9001' },
           headers: { 'X-Sip-Token' => 'a-wrong-token' }

      expect(response).to have_http_status(:unauthorized)
    end

    # --- Event handling: auth is covered above, so bypass the before_action and
    # focus on routing/handler logic. We stub the auth method (not ENV/headers,
    # which don't propagate reliably into the request) so the test is hermetic.
    context 'when the request is authenticated' do
      before do
        # rubocop:disable RSpec/AnyInstance
        allow_any_instance_of(Sip::InternalController)
          .to receive(:authenticate_sip_request!).and_return(true)
        # rubocop:enable RSpec/AnyInstance
      end

      it 'returns 422 for an unknown event type' do
        post events_path, params: { type: 'gibberish' }

        expect(response).to have_http_status(422)
      end

      context 'when the same call_status event is replayed (idempotent by Linkedid)' do
        let(:conversation) { create(:conversation, account: account) }
        let(:call) do
          create(:call,
                 provider: :asterisk,
                 account: account,
                 inbox: conversation.inbox,
                 conversation: conversation,
                 contact: conversation.contact,
                 status: 'ringing',
                 provider_call_id: 'linkedid-abc-123')
        end

        def post_status(status)
          post events_path,
               params: { type: 'call_status', account_id: account.id,
                         call_sid: call.provider_call_id, status: status }
        end

        it 'applies the transition once and ignores the replay without error' do
          post_status('completed')
          expect(response).to have_http_status(:no_content)
          expect(call.reload.status).to eq('completed')

          # Same Linkedid + same terminal status again → no double-apply, no error
          # (CallStatus::Manager short-circuits on a terminal/unchanged status).
          post_status('completed')
          expect(response).to have_http_status(:no_content)
          expect(call.reload.status).to eq('completed')
        end
      end
    end
  end
end
