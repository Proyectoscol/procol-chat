class Contacts::ConversationLabelsPreloader
  def self.call(contact_ids)
    grouped = Hash.new { |hash, key| hash[key] = [] }
    return grouped if contact_ids.blank?

    ActsAsTaggableOn::Tagging
      .joins(:tag)
      .joins("INNER JOIN conversations ON conversations.id = taggings.taggable_id AND taggings.taggable_type = 'Conversation'")
      .where(conversations: { contact_id: contact_ids })
      .pluck('conversations.contact_id', 'tags.name')
      .each_with_object(grouped) { |(contact_id, title), acc| acc[contact_id] << title }
  end
end
