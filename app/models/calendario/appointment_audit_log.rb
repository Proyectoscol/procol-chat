# == Schema Information
#
# Table name: calendario_appointment_audit_logs
#
#  id             :bigint           not null, primary key
#  event_type     :integer          not null
#  from_starts_at :datetime
#  from_status    :integer
#  to_starts_at   :datetime
#  to_status      :integer
#  created_at     :datetime         not null
#  account_id     :bigint           not null
#  appointment_id :bigint           not null
#  user_id        :bigint
#
# Indexes
#
#  index_calendario_appointment_audit_logs_on_account_id      (account_id)
#  index_calendario_appointment_audit_logs_on_appointment_id  (appointment_id)
#  index_calendario_appointment_audit_logs_on_user_id         (user_id)
#  index_calendario_audit_logs_on_appointment_and_event       (appointment_id,event_type)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (appointment_id => calendario_appointments.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class Calendario::AppointmentAuditLog < ApplicationRecord
  self.table_name = 'calendario_appointment_audit_logs'

  enum :event_type, { created: 0, rescheduled: 1, status_changed: 2 }

  belongs_to :account
  belongs_to :appointment, class_name: 'Calendario::Appointment'
  belongs_to :user, optional: true
end
