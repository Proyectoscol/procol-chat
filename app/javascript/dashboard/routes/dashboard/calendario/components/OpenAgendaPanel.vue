<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import WootDatePicker from 'dashboard/components/ui/DatePicker/DatePicker.vue';
import { DATE_RANGE_TYPES } from 'dashboard/components/ui/DatePicker/helpers/DatePickerHelper';

const props = defineProps({
  professionalId: { type: [Number, String], required: true },
});
const emit = defineEmits(['close', 'created']);

const { t } = useI18n();
const store = useStore();

// "YYYY-MM-DD" en hora local -- nunca toISOString(), que correria la fecha
// un dia para cualquier zona negativa (America/Bogota es UTC-5). Mismo bug ya
// corregido en AppointmentFormContent/CancelAppointment para starts_at.
const pad = n => String(n).padStart(2, '0');
const formatDateInput = date =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;

const today = new Date();
const customDateRange = ref([today, today]);
const selectedDateRange = ref(DATE_RANGE_TYPES.CUSTOM_RANGE);
// Sin default a proposito -- la asistente tiene que elegir la franja, un
// clic apurado no debe abrir "manana" por omision.
const timeWindow = ref('');
const isSubmitting = ref(false);

const onDateRangeChange = value => {
  const [startDate, endDate, rangeType] = value;
  customDateRange.value = [startDate, endDate];
  selectedDateRange.value = rangeType || DATE_RANGE_TYPES.CUSTOM_RANGE;
};

const timeWindowOptions = [
  {
    value: 'morning',
    label: 'CALENDARIO.SCHEDULES.OPEN_MULTIPLE.WINDOW_MORNING',
  },
  {
    value: 'afternoon',
    label: 'CALENDARIO.SCHEDULES.OPEN_MULTIPLE.WINDOW_AFTERNOON',
  },
  {
    value: 'full_day',
    label: 'CALENDARIO.SCHEDULES.OPEN_MULTIPLE.WINDOW_FULL_DAY',
  },
];

const matchingDates = computed(() => {
  const [from, to] = customDateRange.value;
  if (!from || !to || from > to) return [];
  const dates = [];
  const cursor = new Date(from);
  while (cursor <= to) {
    dates.push(formatDateInput(cursor));
    cursor.setDate(cursor.getDate() + 1);
  }
  return dates;
});

const isFormInvalid = computed(
  () => !matchingDates.value.length || !timeWindow.value
);

const onClose = () => emit('close');

const submit = async () => {
  isSubmitting.value = true;
  let opened = 0;
  let skipped = 0;
  // Secuencial (no Promise.all): el volumen de un consultorio es bajo y esto
  // evita saturar al servidor con decenas de POST simultaneos.
  // eslint-disable-next-line no-restricted-syntax
  for (const date of matchingDates.value) {
    try {
      // eslint-disable-next-line no-await-in-loop
      await store.dispatch('calendarioOpenDays/create', {
        professional_id: props.professionalId,
        date,
        time_window: timeWindow.value,
      });
      opened += 1;
    } catch (error) {
      if (error?.response?.status === 409) {
        skipped += 1;
      }
    }
  }
  isSubmitting.value = false;
  useAlert(
    t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.SUMMARY', { opened, skipped })
  );
  emit('created');
  onClose();
};
</script>

<template>
  <div
    class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-3 shadow-sm"
  >
    <div class="flex flex-wrap items-end gap-3">
      <div class="flex flex-col gap-1 open-upward">
        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.RANGE_LABEL')
        }}</label>
        <WootDatePicker
          v-model:date-range="customDateRange"
          v-model:range-type="selectedDateRange"
          @date-range-changed="onDateRangeChange"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">{{
          t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.WINDOW_LABEL')
        }}</label>
        <div class="flex gap-1">
          <button
            v-for="option in timeWindowOptions"
            :key="option.value"
            type="button"
            class="px-2.5 py-1.5 text-xs rounded-lg border"
            :class="
              timeWindow === option.value
                ? 'bg-n-blue-9 text-white border-n-blue-9'
                : 'border-n-weak text-n-slate-11'
            "
            @click="timeWindow = option.value"
          >
            {{ t(option.label) }}
          </button>
        </div>
      </div>

      <div class="flex items-center gap-2 ml-auto">
        <Button
          faded
          slate
          size="sm"
          type="button"
          :label="t('CALENDARIO.APPOINTMENTS.FORM.CANCEL')"
          @click="onClose"
        />
        <Button
          size="sm"
          :label="t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.SUBMIT')"
          :is-loading="isSubmitting"
          :disabled="isFormInvalid"
          @click="submit"
        />
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Este panel ya vive pegado al fondo de la pagina (ver CalendarioSchedulesPage
-- se despliega arriba del boton "Abrir agenda") -- el calendario de
WootDatePicker, en cambio, siempre se abre hacia abajo (top-9 fijo), lo que
obligaba a bajar el scroll para verlo y volver a subir para seguir. Se
invierte solo aqui (no en el componente compartido, que otras pantallas
siguen usando hacia abajo sin problema). */
.open-upward :deep(.absolute.top-9) {
  @apply top-auto bottom-9;
}
</style>
