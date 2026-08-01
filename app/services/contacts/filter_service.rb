class Contacts::FilterService < FilterService
  ATTRIBUTE_MODEL = 'contact_attribute'.freeze

  def initialize(account, user, params)
    @account = account
    # TODO: Change the order of arguments in FilterService maybe?
    # account, user, params makes more sense
    super(params, user)
  end

  def perform
    validate_query_operator
    @contacts = query_builder(@filters['contacts'])

    {
      contacts: @contacts,
      count: @contacts.count
    }
  end

  def filter_values(query_hash)
    current_val = query_hash['values'][0]
    if query_hash['attribute_key'] == 'phone_number'
      "+#{current_val&.delete('+')}"
    elsif query_hash['attribute_key'] == 'country_code'
      current_val.downcase
    else
      current_val.is_a?(String) ? current_val.downcase : current_val
    end
  end

  def base_relation
    @account.contacts.resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
  end

  def filter_config
    {
      entity: 'Contact',
      table_name: 'contacts'
    }
  end

  # `labels` (the base FilterService#tag_filter_query) checks tags applied
  # directly to the contact. `conversation_labels` checks tags applied to any
  # of the contact's conversations instead — the labels agents actually set
  # day-to-day from the conversation sidebar.
  def tag_filter_query(query_hash, current_index)
    return super unless query_hash[:attribute_key].to_s == 'conversation_labels'

    query_operator = query_hash[:query_operator]
    @filter_values["value_#{current_index}"] = filter_values(query_hash)

    tag_model_relation_query = <<~SQL.squish
      SELECT 1 FROM conversations
      INNER JOIN taggings ON taggings.taggable_id = conversations.id AND taggings.taggable_type = 'Conversation'
      WHERE conversations.contact_id = contacts.id
    SQL
    tag_query = "AND taggings.tag_id IN (SELECT tags.id FROM tags WHERE tags.name IN (:value_#{current_index}))"

    case query_hash[:filter_operator]
    when 'equal_to'
      "EXISTS (#{tag_model_relation_query} #{tag_query}) #{query_operator}"
    when 'not_equal_to'
      "NOT EXISTS (#{tag_model_relation_query} #{tag_query}) #{query_operator}"
    when 'is_present'
      "EXISTS (#{tag_model_relation_query}) #{query_operator}"
    when 'is_not_present'
      "NOT EXISTS (#{tag_model_relation_query}) #{query_operator}"
    end
  end

  private

  def equals_to_filter_string(filter_operator, current_index)
    return "= :value_#{current_index}" if filter_operator == 'equal_to'

    "!= :value_#{current_index}"
  end
end
