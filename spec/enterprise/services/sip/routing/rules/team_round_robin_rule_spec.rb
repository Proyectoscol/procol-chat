# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sip::Routing::Rules::TeamRoundRobinRule do
  # Concurrency needs COMMITTED data: the worker threads use their own DB
  # connections, and a per-example transaction (transactional fixtures) would hide
  # the records from them. before(:all) commits outside that transaction; the
  # account is left in place on cleanup to avoid FK issues with factory-seeded rows.
  before(:all) do
    @account = create(:account)
    @users = create_list(:user, 3)
    @users.each_with_index do |user, index|
      SipIdentity.create!(
        account: @account,
        user: user,
        sip_extension: "900#{index + 1}",
        sip_active_contacts: 1
      )
    end
  end

  after(:all) do
    SipIdentity.where(account_id: @account.id).delete_all
    User.where(id: @users.map(&:id)).delete_all
  end

  describe '#claim_next_identity (atomic agent claim)' do
    it 'never assigns the same agent to two concurrent calls (no collision)' do
      user_ids = @users.map(&:id)
      results = Concurrent::Array.new
      # CyclicBarrier makes the threads start their claim at the same instant,
      # maximising the real overlap that FOR UPDATE SKIP LOCKED must handle.
      barrier = Concurrent::CyclicBarrier.new(user_ids.size)
      rule = described_class.new

      threads = Array.new(user_ids.size) do
        Thread.new do
          barrier.wait
          ActiveRecord::Base.connection_pool.with_connection do
            row = rule.send(:claim_next_identity, @account.id, user_ids)
            results << row['user_id'].to_i if row
          end
        end
      end
      threads.each(&:join)

      # Each concurrent claim resolved to a DISTINCT agent → zero collisions, and
      # every available agent was claimed exactly once.
      expect(results.size).to eq(user_ids.size)
      expect(results.uniq.size).to eq(user_ids.size)
      expect(results).to match_array(user_ids)
    end
  end
end
