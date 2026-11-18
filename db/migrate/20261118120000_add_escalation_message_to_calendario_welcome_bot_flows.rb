class AddEscalationMessageToCalendarioWelcomeBotFlows < ActiveRecord::Migration[7.1]
  def change
    add_column :calendario_welcome_bot_flows, :escalation_message, :text
  end
end
