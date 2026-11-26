<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import AppointmentDurationStepper from './AppointmentDurationStepper.vue';
import { appointmentWarningMessage } from '../helpers/appointmentWarningMessage';
import { defaultDurationMinutes } from '../helpers/appointmentDuration';

const props = defineProps({
  // { contact_id, contact_name, service_id, professional_id }
  armedEntry: { type: Object, required: true },
  // 'YYYY-MM-DD'
  date: { type: String, required: true },
  // 'HH:MM', precargada segun la ventana del dia (manana/tarde)
  defaultTime: { type: String, required: true },
});
const emit = defineEmits(['booked', 'cancel']);

const { t } = useI18n();
const store = useStore();

const services = useMapGetter('calendarioServices/getServices');
const getContactById = useMapGetter('contacts/getContact');

const time = ref(props.defaultTime);
const isSaving = ref(false);
const warnings = ref([]);

// El contacto puede no estar en el store aun (lista de espera se llena sin
// pasar por la busqueda de contactos) -- si no esta cacheado, cae al
// duration_minutes fijo del servicio, igual que sin pagador conocido.
const durationMinutes = ref(
  defaultDurationMinutes(
    services.value.find(service => service.id === props.armedEntry.service_id),
    props.armedEntry.professional_id,
    getContactById.value(props.armedEntry.contact_id)?.payer_kind
  )
);

const startsAt = () => {
  const [year, month, day] = props.date.split('-').map(Number);
  const [hours, minutes] = time.value.split(':').map(Number);
  return new Date(year, month - 1, day, hours, minutes);
};

const confirm = async () => {
  isSaving.value = true;
  const payload = {
    contact_id: props.armedEntry.contact_id,
    service_id: props.armedEntry.service_id,
    professional_id: props.armedEntry.professional_id,
    starts_at: startsAt().toISOString(),
    ends_at: new Date(
      startsAt().getTime() + durationMinutes.value * 60000
    ).toISOString(),
    // Si ya se mostraron advertencias para este mismo horario, este intento
    // es la confirmacion del usuario -- crear igual (mismo patron que
    // AppointmentFormContent.vue).
    force: warnings.value.length > 0,
  };
  try {
    const appointment = await store.dispatch(
      'calendarioAppointments/create',
      payload
    );
    emit('booked', appointment);
  } catch (error) {
    if (error?.response?.status === 409 && error?.response?.data?.warnings) {
      warnings.value = error.response.data.warnings;
    } else {
      useAlert(
        error?.response?.data?.error ||
          t('CALENDARIO.WAITLIST.QUICK_BOOK.ERROR')
      );
    }
  } finally {
    isSaving.value = false;
  }
};

const warningText = warning => appointmentWarningMessage(t, warning);

const cancel = () => emit('cancel');
</script>

<template>
  <div class="flex flex-col gap-2 rounded-lg border border-n-weak p-3 mt-2">
    <p class="text-xs font-medium text-n-slate-12">
      {{
        t('CALENDARIO.WAITLIST.QUICK_BOOK.TITLE', {
          name: armedEntry.contact_name,
        })
      }}
    </p>
    <div class="flex items-center gap-2">
      <label class="text-xs text-n-slate-11">
        {{ t('CALENDARIO.WAITLIST.QUICK_BOOK.TIME_LABEL') }}
      </label>
      <input
        v-model="time"
        type="time"
        class="rounded-lg border border-n-weak bg-transparent px-2 py-1 text-sm"
      />
    </div>

    <AppointmentDurationStepper v-model="durationMinutes" />

    <p
      v-for="(warning, index) in warnings"
      :key="index"
      class="text-xs text-n-amber-11"
    >
      {{ warningText(warning) }}
    </p>

    <div class="flex items-center justify-end gap-2">
      <Button
        faded
        slate
        size="sm"
        type="button"
        :label="t('CALENDARIO.WAITLIST.QUICK_BOOK.CANCEL')"
        @click="cancel"
      />
      <Button
        size="sm"
        :label="
          warnings.length
            ? t('CALENDARIO.WAITLIST.QUICK_BOOK.CONFIRM_ANYWAY')
            : t('CALENDARIO.WAITLIST.QUICK_BOOK.CONFIRM')
        "
        :is-loading="isSaving"
        @click="confirm"
      />
    </div>
  </div>
</template>
