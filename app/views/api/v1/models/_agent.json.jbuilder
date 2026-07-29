json.id resource.id
# could be nil for a deleted agent hence the safe operator before account id
json.account_id Current.account&.id
json.availability_status resource.availability_status
json.auto_offline resource.auto_offline
json.confirmed resource.confirmed?
json.email resource.email
json.provider resource.provider
json.available_name resource.available_name
json.custom_attributes resource.custom_attributes if resource.custom_attributes.present?
json.name resource.name
json.role resource.role
json.thumbnail resource.avatar_url
json.teams(resource.teams.where(account_id: Current.account&.id).map { |team| { id: team.id, name: team.name } })
json.custom_role_id resource.current_account_user&.custom_role_id if ChatwootApp.enterprise?
if ChatwootApp.enterprise?
  sip = resource.sip_identities.find { |s| s.account_id == Current.account.id }
  json.sip_extension sip&.sip_extension
  json.sip_active sip ? !sip.sip_absence_mode : nil
end
