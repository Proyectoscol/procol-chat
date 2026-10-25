# frozen_string_literal: true

FactoryBot.define do
  factory :inbox do
    account
    channel { FactoryBot.build(:channel_widget, account: account) }
    # sequence, no un string fijo -- Team tiene un mirror 1:1 por inbox (ver
    # InboxMirrorTeam) con nombre unico por cuenta; 2+ inboxes con el mismo
    # nombre por defecto para la misma account revientan al crear el
    # segundo Team espejo ("Name has already been taken").
    sequence(:name) { |n| "Inbox #{n}" }

    after(:create) do |inbox|
      inbox.channel.save!
    end

    trait :with_email do
      channel { FactoryBot.build(:channel_email, account: account) }
      name { 'Email Inbox' }
    end
  end
end
