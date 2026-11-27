<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import DatePicker from 'vue-datepicker-next';
import {
  formatInstantDateTimeEs,
  formatDateOnlyEs,
  dateKeyInColombia,
} from '../helpers/calendarioDateTime';
import { ES_DATEPICKER_LANG } from '../helpers/datepickerLang';
import AppointmentDurationStepper from './AppointmentDurationStepper.vue';

const props = defineProps({
  appointment: { type: Object, required: true },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const openDays = useMapGetter('calendarioOpenDays/getOpenDays');

// Preserva la duracion que ya tenia la cita -- reagendar normalmente solo
// mueve el horario, pero el agente puede ajustarla con el stepper si la
// nueva franja necesita ser mas corta/larga.
const durationMinutes = ref(
  Math.round(
    (new Date(props.appointment.ends_at) -
      new Date(props.appointment.starts_at)) /
      60000
  )
);

const startsAt = ref(new Date(props.appointment.starts_at));
const notes = ref(props.appointment.notes || '');
const isSaving = ref(false);
const appointmentWarnings = ref([]);

const isFormInvalid = computed(() => !startsAt.value || !notes.value.trim());

// El profesional no cambia al reagendar -- se traen sus dias con agenda
// abierta una sola vez, al montar (mismo criterio visual que
// AppointmentFormContent: color mas vivo en el date picker).
onMounted(() => {
  store.dispatch('calendarioOpenDays/get', {
    professionalId: props.appointment.professional_id,
  });
});
const openDayDates = computed(() => new Set(openDays.value.map(d => d.date)));
const getDayClasses = (value, _innerValue, classes) =>
  openDayDates.value.has(dateKeyInColombia(value))
    ? `${classes} has-open-day`.trim()
    : classes;

const warningMessage = warning => {
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

const onClose = () => emit('close');

const submit = async () => {
  if (isSaving.value) return;
  isSaving.value = true;
  const newStartsAt = startsAt.value;
  const newEndsAt = new Date(
    newStartsAt.getTime() + durationMinutes.value * 60000
  );
  try {
    await store.dispatch('calendarioAppointments/update', {
      id: props.appointment.id,
      starts_at: newStartsAt.toISOString(),
      ends_at: newEndsAt.toISOString(),
      notes: notes.value,
      force: appointmentWarnings.value.length > 0,
    });
    useAlert(t('CALENDARIO.APPOINTMENTS.RESCHEDULE.SUCCESS'));
    onClose();
  } catch (error) {
    if (error?.response?.status === 409 && error?.response?.data?.warnings) {
      appointmentWarnings.value = error.response.data.warnings;
    } else {
      useAlert(
        error?.response?.data?.error ||
          t('CALENDARIO.APPOINTMENTS.RESCHEDULE.ERROR')
      );
    }
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <form class="flex flex-col gap-4 w-full" @submit.prevent="submit">
    <div class="flex flex-col gap-1">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('CALENDARIO.APPOINTMENTS.FORM.STARTS_AT_LABEL') }}
      </label>
      <DatePicker
        v-model:value="startsAt"
        type="datetime"
        :lang="ES_DATEPICKER_LANG"
        format="DD/MM/YYYY hh:mm A"
        use12h
        :minute-step="10"
        confirm
        confirm-text="OK"
        :get-classes="getDayClasses"
        input-class="w-full rounded-lg border border-n-weak bg-transparent px-3 py-2 text-sm"
      />
      <p class="text-xs text-n-slate-10">
        {{ t('CALENDARIO.APPOINTMENTS.FORM.OPEN_DAY_HINT') }}
      </p>
    </div>

    <AppointmentDurationStepper v-model="durationMinutes" />

    <TextArea
      v-model="notes"
      :label="t('CALENDARIO.APPOINTMENTS.RESCHEDULE.NOTES_LABEL')"
      :placeholder="t('CALENDARIO.APPOINTMENTS.RESCHEDULE.NOTES_PLACEHOLDER')"
      :max-length="500"
    />

    <div
      v-if="appointmentWarnings.length"
      class="flex flex-col gap-2 text-sm text-n-amber-11 bg-n-amber-3 rounded-lg p-3"
    >
      <p v-for="(warning, index) in appointmentWarnings" :key="index">
        {{ warningMessage(warning) }}
      </p>
    </div>

    <div class="flex items-center justify-end gap-2">
      <Button
        faded
        slate
        type="button"
        :label="t('CALENDARIO.APPOINTMENTS.FORM.CANCEL')"
        @click="onClose"
      />
      <Button
        type="submit"
        :label="
          appointmentWarnings.length
            ? t('CALENDARIO.APPOINTMENTS.FORM.CONFIRM_ANYWAY')
            : t('CALENDARIO.APPOINTMENTS.RESCHEDULE.SUBMIT')
        "
        :is-loading="isSaving"
        :disabled="isFormInvalid || isSaving"
      />
    </div>
  </form>
</template>

<style>
/* vue-datepicker-next monta su popup como hijo directo de <body> (fuera del
arbol del componente) -- un estilo "scoped" normal nunca llegaria porque
depende de un ancestro con el atributo data-v-*, asi que esta regla queda
global a proposito. El nombre de clase es especifico de este feature para
evitar colisiones. */
td.cell.has-open-day {
  @apply bg-n-teal-9 text-white rounded-full font-semibold;
}
</style>
