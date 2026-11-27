<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  professional: { type: Object, required: true },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const availabilities = useMapGetter(
  'calendarioProfessionalAvailabilities/getAvailabilities'
);
const uiFlags = useMapGetter('calendarioProfessionalAvailabilities/getUIFlags');

// Sin fecha de corte real en esta UI (fuera de alcance de Fase 1) -- 2 anios
// hacia adelante funciona como "sin fecha de fin" en la practica.
const farFutureDate = () => {
  const date = new Date();
  date.setFullYear(date.getFullYear() + 2);
  return date.toISOString().slice(0, 10);
};
const today = () => new Date().toISOString().slice(0, 10);

const WEEKDAY_LABELS = [
  'SUNDAY',
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
];

const selectedWeekdays = ref([1, 2, 3, 4, 5]);
const startTime = ref('09:00');
const endTime = ref('17:00');
const startsOn = ref(today());
const endsOn = ref(farFutureDate());
const isSaving = ref(false);

const toggleWeekday = day => {
  selectedWeekdays.value = selectedWeekdays.value.includes(day)
    ? selectedWeekdays.value.filter(existing => existing !== day)
    : [...selectedWeekdays.value, day];
};

const weekdayLabel = days =>
  days
    .slice()
    .sort()
    .map(day =>
      t(
        `CALENDARIO.PROFESSIONALS.AVAILABILITY.WEEKDAYS_SHORT.${WEEKDAY_LABELS[day]}`
      )
    )
    .join(', ');

const isFormInvalid = computed(
  () =>
    selectedWeekdays.value.length === 0 ||
    !startTime.value ||
    !endTime.value ||
    endTime.value <= startTime.value
);

const onClose = () => emit('close');

const addWindow = async () => {
  if (isSaving.value) return;
  isSaving.value = true;
  try {
    await store.dispatch('calendarioProfessionalAvailabilities/create', {
      professionalId: props.professional.id,
      weekdays: selectedWeekdays.value,
      start_time: startTime.value,
      end_time: endTime.value,
      starts_on: startsOn.value,
      ends_on: endsOn.value,
    });
    useAlert(t('CALENDARIO.PROFESSIONALS.AVAILABILITY.CREATE_SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CALENDARIO.PROFESSIONALS.AVAILABILITY.ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

const removeWindow = async availability => {
  try {
    await store.dispatch('calendarioProfessionalAvailabilities/delete', {
      professionalId: props.professional.id,
      id: availability.id,
    });
  } catch (error) {
    useAlert(t('CALENDARIO.PROFESSIONALS.AVAILABILITY.DELETE_ERROR'));
  }
};

onMounted(() => {
  store.dispatch(
    'calendarioProfessionalAvailabilities/get',
    props.professional.id
  );
});
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="
        t('CALENDARIO.PROFESSIONALS.AVAILABILITY.TITLE', {
          name: professional.name,
        })
      "
    />
    <div class="flex flex-col gap-4 px-4 pb-4 w-full !self-stretch">
      <p class="text-sm text-n-slate-11">
        {{ t('CALENDARIO.PROFESSIONALS.AVAILABILITY.DESCRIPTION') }}
      </p>

      <div v-if="availabilities.length" class="flex flex-col gap-2">
        <div
          v-for="availability in availabilities"
          :key="availability.id"
          class="flex items-center justify-between gap-2 rounded-lg border border-n-weak p-2"
        >
          <div class="text-sm">
            <span class="font-medium text-n-slate-12">{{
              weekdayLabel(availability.weekdays)
            }}</span>
            <span class="text-n-slate-11">
              · {{ availability.start_time }} –
              {{ availability.end_time }}
            </span>
          </div>
          <Button
            icon="i-woot-bin"
            slate
            sm
            @click="removeWindow(availability)"
          />
        </div>
      </div>
      <p v-else class="text-sm text-n-slate-10">
        {{ t('CALENDARIO.PROFESSIONALS.AVAILABILITY.EMPTY') }}
      </p>

      <div class="flex flex-col gap-3 rounded-lg border border-n-weak p-3">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.PROFESSIONALS.AVAILABILITY.WEEKDAYS_LABEL') }}
        </label>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="(label, day) in WEEKDAY_LABELS"
            :key="day"
            type="button"
            class="px-2 py-1 text-xs rounded-lg border"
            :class="
              selectedWeekdays.includes(day)
                ? 'bg-n-blue-9 text-white border-n-blue-9'
                : 'border-n-weak text-n-slate-11'
            "
            @click="toggleWeekday(day)"
          >
            {{
              t(`CALENDARIO.PROFESSIONALS.AVAILABILITY.WEEKDAYS_SHORT.${label}`)
            }}
          </button>
        </div>

        <div class="flex gap-3">
          <div class="flex flex-col gap-1 flex-1">
            <label class="text-xs text-n-slate-11">{{
              t('CALENDARIO.PROFESSIONALS.AVAILABILITY.START_TIME_LABEL')
            }}</label>
            <input
              v-model="startTime"
              type="time"
              class="rounded-lg border border-n-weak px-2 py-1 text-sm"
            />
          </div>
          <div class="flex flex-col gap-1 flex-1">
            <label class="text-xs text-n-slate-11">{{
              t('CALENDARIO.PROFESSIONALS.AVAILABILITY.END_TIME_LABEL')
            }}</label>
            <input
              v-model="endTime"
              type="time"
              class="rounded-lg border border-n-weak px-2 py-1 text-sm"
            />
          </div>
        </div>

        <Button
          size="sm"
          :label="t('CALENDARIO.PROFESSIONALS.AVAILABILITY.ADD_BUTTON')"
          :is-loading="isSaving || uiFlags.isCreating"
          :disabled="isFormInvalid || isSaving"
          @click="addWindow"
        />
      </div>

      <div class="flex items-center justify-end">
        <Button
          faded
          slate
          :label="t('CALENDARIO.PROFESSIONALS.AVAILABILITY.CLOSE')"
          @click="onClose"
        />
      </div>
    </div>
  </div>
</template>
