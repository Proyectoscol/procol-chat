# == Schema Information
#
# Table name: email_templates
#
#  id            :bigint           not null, primary key
#  body          :text             not null
#  locale        :integer          default("en"), not null
#  name          :string           not null
#  template_type :integer          default("content")
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :integer
#  inbox_id      :integer
#
# Indexes
#
#  index_email_templates_on_account_scope       (account_id,name,template_type,locale) UNIQUE WHERE ((account_id IS NOT NULL) AND (inbox_id IS NULL))
#  index_email_templates_on_inbox_id            (inbox_id)
#  index_email_templates_on_inbox_scope         (inbox_id,name,template_type,locale) UNIQUE WHERE (inbox_id IS NOT NULL)
#  index_email_templates_on_installation_scope  (name,template_type,locale) UNIQUE WHERE ((account_id IS NULL) AND (inbox_id IS NULL))
#
class EmailTemplate < ApplicationRecord
  enum :locale, LANGUAGES_CONFIG.map { |key, val| [val[:iso_639_1_code], key] }.to_h, prefix: true
  enum :template_type, { layout: 0, content: 1 }
  belongs_to :account, optional: true

  validates :name, uniqueness: { scope: :account }

  def self.resolver(options = {})
    ::EmailTemplates::DbResolverService.using self, options
  end
end
