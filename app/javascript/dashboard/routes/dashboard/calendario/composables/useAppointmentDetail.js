import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import CalendarioAppointmentsAPI from 'dashboard/api/calendarioAppointments';
import {
  statusSelectOptions,
  rescheduleCountLabel as buildRescheduleCountLabel,
} from '../helpers/appointmentStatusActions';
import { formatInstantDateTimeEs } from '../helpers/calendarioDateTime';

// Logica compartida entre AppointmentDetailModal (centrado, para Citas/Agenda)
// y AppointmentDetailDrawer (panel lateral, para la conversacion -- ahi un
// modal centrado tapa el chat que el agente necesita seguir viendo mientras
// reagenda). Las dos vistas comparten todo menos el "chrome" de presentacion.
export function useAppointmentDetail(appointmentId, { onChanged } = {}) {
  const { t } = useI18n();
  const store = useStore();

  const isFetching = ref(true);
  const isUpdatingStatus = ref(false);
  const appointment = ref(null);

  const statusLabel = status =>
    t(`CALENDARIO.APPOINTMENTS.STATUS.${status.toUpperCase()}`);

  const formatDateTime = value => formatInstantDateTimeEs(value);

  const rescheduleCountLabel = count => buildRescheduleCountLabel(t, count);

  const historyLabel = entry => {
    if (entry.event_type === 'created') {
      return t('CALENDARIO.APPOINTMENTS.DETAIL.HISTORY.CREATED');
    }
    if (entry.event_type === 'rescheduled') {
      return t('CALENDARIO.APPOINTMENTS.DETAIL.HISTORY.RESCHEDULED', {
        from: formatDateTime(entry.from_starts_at),
        to: formatDateTime(entry.to_starts_at),
      });
    }
    return t('CALENDARIO.APPOINTMENTS.DETAIL.HISTORY.STATUS_CHANGED', {
      from: statusLabel(entry.from_status),
      to: statusLabel(entry.to_status),
    });
  };

  const fetchDetail = async () => {
    isFetching.value = true;
    try {
      const response = await CalendarioAppointmentsAPI.show(appointmentId);
      appointment.value = response.data;
    } catch (error) {
      useAlert(t('CALENDARIO.APPOINTMENTS.DETAIL.FETCH_ERROR'));
    } finally {
      isFetching.value = false;
    }
  };

  const setStatus = async status => {
    isUpdatingStatus.value = true;
    try {
      const updated = await store.dispatch('calendarioAppointments/update', {
        id: appointment.value.id,
        status,
      });
      appointment.value = { ...appointment.value, ...updated };
      onChanged?.();
    } catch (error) {
      useAlert(
        error?.response?.data?.error ||
          t('CALENDARIO.APPOINTMENTS.UPDATE_ERROR')
      );
    } finally {
      isUpdatingStatus.value = false;
    }
  };

  const statusOptions = computed(() => statusSelectOptions(t));

  fetchDetail();

  return {
    isFetching,
    isUpdatingStatus,
    appointment,
    statusOptions,
    statusLabel,
    formatDateTime,
    rescheduleCountLabel,
    historyLabel,
    setStatus,
  };
}
