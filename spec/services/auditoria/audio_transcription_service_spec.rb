require 'rails_helper'

RSpec.describe Auditoria::AudioTranscriptionService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
  let!(:attachment) { message.attachments.create!(account: account, file_type: :audio) }
  let(:service) { described_class.new(account: account, message: message) }

  before do
    allow(Auditoria::AiUsageLogger).to receive(:within_limit?).and_return(true)
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
    # destroy_all + create (no find_or_create_by!) -- un registro ya
    # existente con value nil (ej. de una corrida anterior que no limpio)
    # haria que find_or_create_by! lo devolviera tal cual sin el value que
    # este spec necesita.
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
  end

  describe '#perform' do
    it 'calls transcribe and releases the lock afterwards so a later call can proceed' do
      allow(service).to receive(:transcribe).and_return({ text: 'hello' })

      expect(service.perform).to eq({ text: 'hello' })
      expect(Redis::Alfred.get(format(Redis::RedisKeys::AUDITORIA_AUDIO_TRANSCRIPTION_LOCK, id: attachment.id))).to be_nil
    end

    it 'skips transcription when another call already claimed this attachment' do
      other_service = described_class.new(account: account, message: message)
      allow(other_service).to receive(:transcribe)
      other_service.send(:claim_attachment!) # simulates the other call having already claimed it, without releasing yet

      expect(service).not_to receive(:transcribe)
      expect(service.perform).to eq({ error: 'Already transcribing' })
    end

    it 'releases the lock even when transcribe raises' do
      allow(service).to receive(:transcribe).and_raise(StandardError, 'boom')
      allow(service).to receive(:capture_llm_exception)

      expect(service.perform).to eq({ error: 'boom' })
      expect(Redis::Alfred.get(format(Redis::RedisKeys::AUDITORIA_AUDIO_TRANSCRIPTION_LOCK, id: attachment.id))).to be_nil
    end
  end
end
