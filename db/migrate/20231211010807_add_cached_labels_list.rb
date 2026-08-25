class AddCachedLabelsList < ActiveRecord::Migration[7.0]
  # ActsAsTaggableOn::Taggable::Cache no longer exists as of acts-as-taggable-on
  # 12 — caching is auto-detected from the `cached_#{context}_list` column
  # (see Taggable::Caching#caching_tag_list_on?), so no explicit include is
  # needed once the column below exists.
  def change
    add_column :conversations, :cached_label_list, :string
    Conversation.reset_column_information
  end
end
