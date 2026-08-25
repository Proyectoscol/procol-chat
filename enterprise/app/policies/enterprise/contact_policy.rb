module Enterprise::ContactPolicy
  def export?
    @account_user.custom_role&.permissions&.include?('contact_manage') || super
  end

  def import?
    @account_user.custom_role&.permissions&.include?('contact_manage') || super
  end

  def attribute_stats?
    @account_user.custom_role&.permissions&.include?('lead_stats_manage') || super
  end

  def lead_stats_contacts?
    @account_user.custom_role&.permissions&.include?('lead_stats_manage') || super
  end

  def lead_stats_export?
    @account_user.custom_role&.permissions&.include?('lead_stats_manage') || super
  end
end
