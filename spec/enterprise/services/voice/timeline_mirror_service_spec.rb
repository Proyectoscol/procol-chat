# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Voice::TimelineMirrorService do
  let(:account) { create(:account) }
  let!(:voice_channel) { Channel::Voice.create!(account: account, phone_number: '+576000000001') }
  let!(:inbox) { create(:inbox, account: account, channel: voice_channel) }
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

  def perform
    described_class.perform(payload)
  end

  context 'contacto con conversacion WhatsApp activa' do
    let(:whatsapp_channel) do
      create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
    end
    let(:whatsapp_inbox) { whatsapp_channel.inbox }
    let!(:contact) { create(:contact, account: account, phone_number: '+573006649923') }
    let!(:wa_conversation) do
      create(:conversation, account: account, inbox: whatsapp_inbox, contact: contact, status: :open)
    end

    it 'agrega la activity a la conversacion WhatsApp existente' do
      expect { perform }
        .to change { wa_conversation.reload.messages.where(message_type: :activity).count }.by(1)
    end

    it 'no crea una nueva conversacion' do
      expect { perform }.not_to change(account.conversations, :count)
    end
  end

  context 'contacto sin conversacion abierta' do
    let!(:contact) { create(:contact, account: account, phone_number: '+573006649923') }

    it 'crea conversacion en el inbox Channel::Voice y agrega activity' do
      expect { perform }
        .to change(account.conversations, :count).by(1)
        .and change(Message, :count).by(1)

      new_conv = account.conversations.last
      expect(new_conv.inbox).to eq(inbox)
      expect(new_conv.messages.last.message_type).to eq('activity')
    end
  end

  context 'numero desconocido' do
    it 'crea contacto, crea conversacion y agrega activity' do
      expect { perform }
        .to change(account.contacts, :count).by(1)
        .and change(account.conversations, :count).by(1)
        .and change(Message, :count).by(1)

      new_contact = account.contacts.find_by(phone_number: '+573006649923')
      expect(new_contact).to be_present
      expect(account.conversations.last.contact).to eq(new_contact)
    end
  end
end
