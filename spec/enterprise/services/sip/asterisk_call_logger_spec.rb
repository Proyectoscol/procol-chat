# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sip::AsteriskCallLogger do
  let(:account) { create(:account) }
  let(:voice_channel) { Channel::Voice.create!(account: account, phone_number: '+576000000001') }
  let(:inbox) { create(:inbox, account: account, channel: voice_channel) }
  let(:payload) do
    {
      'event_type'       => 'ended',
      'from_number'      => '+573006649923',
      'to'               => '+576000000001',
      'call_direction'   => 'inbound',
      'duration_seconds' => 47,
      'linkedid'         => 'linkedid-xyz'
    }
  end

  def call_logger
    described_class.call(inbox: inbox, payload: payload)
  end

  it 'crea un registro Call con estado completed' do
    call = call_logger

    aggregate_failures do
      expect(call).to be_a(Call)
      expect(call.status).to eq('completed')
      expect(call.provider).to eq('asterisk')
      expect(call.direction).to eq('incoming')
      expect(call.duration_seconds).to eq(47)
      expect(call.provider_call_id).to eq('linkedid-xyz')
      expect(call.contact.phone_number).to eq('+573006649923')
    end
  end

  it 'es idempotente con el mismo linkedid' do
    first = call_logger

    second = nil
    expect { second = call_logger }.not_to change(Call, :count)
    expect(second).to eq(first)
  end

  it 'marca como no_answer cuando duration_seconds es 0' do
    payload['duration_seconds'] = 0

    call = call_logger

    expect(call.status).to eq('no_answer')
  end
end
