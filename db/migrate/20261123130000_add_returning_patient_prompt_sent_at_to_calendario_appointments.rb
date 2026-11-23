class AddReturningPatientPromptSentAtToCalendarioAppointments < ActiveRecord::Migration[7.1]
  def change
    add_column :calendario_appointments, :returning_patient_prompt_sent_at, :datetime
  end
end
