json.meta do
  json.total_count @contacts_count
  json.current_page @current_page.to_i
end

json.payload do
  json.array! @contacts do |contact|
    json.id contact.id
    json.name contact.name
    json.email contact.email
    json.phone_number contact.phone_number
    json.thumbnail contact.avatar_url
    json.created_at contact.created_at.to_i
    json.additional_attributes contact.additional_attributes
    json.custom_attributes contact.custom_attributes
    json.labels @contact_labels_by_id.fetch(contact.id, [])
  end
end
