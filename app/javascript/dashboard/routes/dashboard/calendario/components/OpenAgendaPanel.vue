<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import DatePicker from 'vue-datepicker-next';
import { ES_DATEPICKER_LANG } from '../helpers/datepickerLang';

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

// Antes pedia un RANGO (fecha inicio + fecha fin) aunque el 95% de las veces
// se usa para un solo dia -- pedido explicito del usuario: "no me interesa
// que yo tenga que darle dos veces click... debería solamente pedirme una
// vez click en el calendario". Una sola fecha (no Date|null) en vez de
// [from, to]; matchingDates de abajo sigue funcionando igual (un rango de
// un solo dia), asi que el submit/la logica de creacion no cambia.
const selectedDate = ref(new Date());
// Sin default a proposito -- la asistente tiene que elegir la franja, un
// clic apurado no debe abrir "manana" por omision.
const timeWindow = ref('');
const notes = ref('');
const isSubmitting = ref(false);

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

// Sigue llamandose "matchingDates" (array) aunque ahora siempre tiene como
// mucho un elemento -- asi el submit de abajo no cambia nada.
const matchingDates = computed(() =>
  selectedDate.value ? [formatDateInput(selectedDate.value)] : []
);

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
        notes: notes.value || null,
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
    class="flex flex-col gap-6 items-center justify-center w-full h-full p-6"
  >
    <h2 class="text-lg font-semibold text-n-slate-12">
      {{ t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.TITLE') }}
    </h2>

    <div class="flex flex-col gap-6 w-full max-w-sm">
      <div class="flex flex-col gap-1">
        <span
          class="text-xs font-medium text-n-slate-11 uppercase tracking-wide"
        >
          {{ t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.STEP_1') }}
        </span>
        <label class="text-sm text-n-slate-12">{{
          t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.DATE_LABEL')
        }}</label>
        <DatePicker
          v-model:value="selectedDate"
          type="date"
          :lang="ES_DATEPICKER_LANG"
          format="DD/MM/YYYY"
          input-class="w-full rounded-lg border border-n-weak bg-transparent px-3 py-2 text-sm"
        />
      </div>

      <div class="flex flex-col gap-1">
        <span
          class="text-xs font-medium text-n-slate-11 uppercase tracking-wide"
        >
          {{ t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.STEP_2') }}
        </span>
        <label class="text-sm text-n-slate-12">{{
          t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.WINDOW_LABEL')
        }}</label>
        <div class="flex gap-1">
          <button
            v-for="option in timeWindowOptions"
            :key="option.value"
            type="button"
            class="flex-1 px-2.5 py-2 text-sm rounded-lg border"
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

      <TextArea
        v-model="notes"
        :label="t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.NOTES_LABEL')"
        :max-length="500"
      />
    </div>

    <div class="flex items-center gap-2">
      <Button
        faded
        slate
        type="button"
        :label="t('CALENDARIO.APPOINTMENTS.FORM.CANCEL')"
        @click="onClose"
      />
      <Button
        :label="t('CALENDARIO.SCHEDULES.OPEN_MULTIPLE.SUBMIT')"
        :is-loading="isSubmitting"
        :disabled="isFormInvalid"
        @click="submit"
      />
    </div>
  </div>
</template>
