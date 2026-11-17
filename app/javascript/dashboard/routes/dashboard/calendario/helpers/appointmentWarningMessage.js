import {
  formatInstantDateTimeEs,
  formatDateOnlyEs,
} from './calendarioDateTime';

// Traduce una advertencia de Calendario::AppointmentWarningsFinder (409 al
// crear una cita) a un mensaje legible -- compartido entre AppointmentFormContent
// y el popover de agendar rapido desde la lista de espera, para que ambos
// muestren exactamente el mismo texto ante el mismo tipo de advertencia.
export const appointmentWarningMessage = (t, warning) => {
  if (warning.type === 'outside_availability') {
    return t('CALENDARIO.APPOINTMENTS.FORM.OUTSIDE_AVAILABILITY_WARNING');
  }
  if (warning.type === 'open_day_missing') {
    return t('CALENDARIO.APPOINTMENTS.FORM.OPEN_DAY_MISSING_WARNING', {
      date: formatDateOnlyEs(warning.date, {
        weekday: 'long',
        day: 'numeric',
        month: 'long',
      }),
      window: t(
        `CALENDARIO.SCHEDULES.TIME_WINDOW.${warning.time_window.toUpperCase()}`
      ),
    });
  }
  const i18nKey =
    warning.type === 'contact_conflict'
      ? 'CALENDARIO.APPOINTMENTS.FORM.CONTACT_CONFLICT_WARNING'
      : 'CALENDARIO.APPOINTMENTS.FORM.OVERLAP_WARNING';
  return t(i18nKey, {
    contact: warning.conflict.contact_name,
    when: formatInstantDateTimeEs(warning.conflict.starts_at),
  });
};
