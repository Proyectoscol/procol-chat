class Contacts::PermissionFilterService
  attr_reader :contacts, :user, :account

  def initialize(contacts, user, account)
    @contacts = contacts
    @user = user
    @account = account
  end

  # Los contactos son compartidos entre todo el equipo por diseno de
  # Chatwoot (a diferencia de las conversaciones) -- esta restriccion solo
  # aplica a un administrator con restricted_inbox_ids (ver AccountUser),
  # nunca a un agent ni a un admin sin restriccion.
  def perform
    return contacts unless account_user&.inbox_restricted?

    contacts.where(id: Conversation.where(inbox_id: account_user.restricted_inbox_ids).select(:contact_id))
  end

  private

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end
end
