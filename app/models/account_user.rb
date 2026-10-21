# == Schema Information
#
# Table name: account_users
#
#  id                       :bigint           not null, primary key
#  active_at                :datetime
#  auto_offline             :boolean          default(TRUE), not null
#  availability             :integer          default("online"), not null
#  restricted_inbox_ids     :integer          default([]), not null, is an Array
#  role                     :integer          default("agent")
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint
#  agent_capacity_policy_id :bigint
#  custom_role_id           :bigint
#  inviter_id               :bigint
#  user_id                  :bigint
#
# Indexes
#
#  index_account_users_on_account_id                (account_id)
#  index_account_users_on_agent_capacity_policy_id  (agent_capacity_policy_id)
#  index_account_users_on_custom_role_id            (custom_role_id)
#  index_account_users_on_restricted_inbox_ids      (restricted_inbox_ids) USING gin
#  index_account_users_on_user_id                   (user_id)
#  uniq_user_id_per_account_id                      (account_id,user_id) UNIQUE
#

class AccountUser < ApplicationRecord
  include AvailabilityStatusable

  belongs_to :account
  belongs_to :user
  belongs_to :inviter, class_name: 'User', optional: true

  enum role: { agent: 0, administrator: 1 }
  enum availability: { online: 0, offline: 1, busy: 2 }

  accepts_nested_attributes_for :account

  # Solo tiene sentido para administrator (un agent ya tiene su alcance via
  # InboxMember) -- si el rol cambia a agent, se limpia para no dejar un
  # estado inconsistente si mas tarde vuelve a ser administrator.
  before_validation :clear_restricted_inbox_ids_unless_administrator

  after_create_commit :notify_creation, :create_notification_setting, :create_auditoria_assignment_rule
  after_destroy :notify_deletion, :remove_user_from_account
  after_save :update_presence_in_redis, if: :saved_change_to_availability?
  after_commit :invalidate_filtered_unread_count_visibility, on: [:create, :destroy]
  after_update_commit :invalidate_filtered_unread_count_visibility_update, if: :filtered_unread_count_visibility_changed?

  validates :user_id, uniqueness: { scope: :account_id }

  def create_notification_setting
    setting = user.notification_settings.new(account_id: account.id)
    setting.selected_email_flags = [:email_conversation_assignment]
    setting.selected_push_flags = [:push_conversation_assignment]
    setting.save!
  end

  def remove_user_from_account
    ::Agents::DestroyJob.perform_later(account, user)
  end

  # Auditoria agents are proxies for a WhatsApp source: the external platform
  # tags every message it replicates with "Source: <agent name>", so each
  # agent needs a matching rule to self-assign that conversation on creation.
  # Shape of the rule lives in Auditoria::AgentReconcilerService, which also
  # backfills it in bulk for agents that already existed before this feature.
  def create_auditoria_assignment_rule
    return unless account.feature_enabled?('auditoria')
    return if auditoria_assignment_rule_exists?

    Auditoria::AgentReconcilerService.create_assignment_rule!(account: account, user: user)
  end

  def permissions
    administrator? ? ['administrator'] : ['agent']
  end

  def inbox_restricted?
    administrator? && restricted_inbox_ids.present?
  end

  def accessible_inboxes
    inbox_restricted? ? account.inboxes.where(id: restricted_inbox_ids) : account.inboxes
  end

  def user_in_scope?(target_user)
    !inbox_restricted? || InboxMember.exists?(user_id: target_user.id, inbox_id: restricted_inbox_ids)
  end

  def push_event_data
    {
      id: id,
      availability: availability,
      role: role,
      user_id: user_id
    }
  end

  private

  def clear_restricted_inbox_ids_unless_administrator
    self.restricted_inbox_ids = [] unless administrator?
  end

  # Si el agente ya tuvo una regla antes (por ejemplo, removido y
  # re-agregado a la cuenta) comparamos ignorando tildes/mayusculas/espacios
  # -- ver Auditoria::MessageAnnotatorService.normalize_name -- para no
  # crear una duplicada.
  def auditoria_assignment_rule_exists?
    normalized_tag = Auditoria::MessageAnnotatorService.normalize_name(Auditoria::AgentReconcilerService.source_tag_for(user))
    account.automation_rules.where(event_name: 'message_created').any? do |rule|
      Auditoria::MessageAnnotatorService.normalize_name(rule.description) == normalized_tag
    end
  end

  def notify_creation
    Rails.configuration.dispatcher.dispatch(AGENT_ADDED, Time.zone.now, account: account)
  end

  def notify_deletion
    Rails.configuration.dispatcher.dispatch(AGENT_REMOVED, Time.zone.now, account: account)
  end

  def update_presence_in_redis
    OnlineStatusTracker.set_status(account.id, user.id, availability)
  end

  def filtered_unread_count_visibility_changed?
    previous_changes.key?('role') || previous_changes.key?('custom_role_id')
  end

  def invalidate_filtered_unread_count_visibility
    ::Conversations::UnreadCounts::FilteredCountInvalidator.new(account).user_visibility_changed!(user_id: user_id)
  end

  def invalidate_filtered_unread_count_visibility_update
    dispatch_account_cache_invalidated if invalidate_filtered_unread_count_visibility
  end

  def dispatch_account_cache_invalidated
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CACHE_INVALIDATED, Time.zone.now, account: account, cache_keys: account.cache_keys)
  end
end

AccountUser.prepend_mod_with('AccountUser')
AccountUser.include_mod_with('Audit::AccountUser')
AccountUser.include_mod_with('Concerns::AccountUser')
