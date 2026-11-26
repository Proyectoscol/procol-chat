<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  MIN_DURATION_MINUTES,
  MAX_DURATION_MINUTES,
  DURATION_STEP_MINUTES,
  clampDurationMinutes,
} from '../helpers/appointmentDuration';

const props = defineProps({
  modelValue: { type: Number, required: true },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const adjust = delta => {
  emit('update:modelValue', clampDurationMinutes(props.modelValue + delta));
};
</script>

<template>
  <div class="flex flex-col gap-1">
    <label class="text-sm font-medium text-n-slate-12">
      {{ t('CALENDARIO.APPOINTMENTS.FORM.DURATION_LABEL') }}
    </label>
    <div class="flex items-center gap-2">
      <Button
        type="button"
        faded
        slate
        size="sm"
        icon="i-lucide-minus"
        :disabled="modelValue <= MIN_DURATION_MINUTES"
        @click="adjust(-DURATION_STEP_MINUTES)"
      />
      <span class="text-sm font-medium text-n-slate-12 w-20 text-center">
        {{
          t('CALENDARIO.APPOINTMENTS.FORM.DURATION_MINUTES', {
            minutes: modelValue,
          })
        }}
      </span>
      <Button
        type="button"
        faded
        slate
        size="sm"
        icon="i-lucide-plus"
        :disabled="modelValue >= MAX_DURATION_MINUTES"
        @click="adjust(DURATION_STEP_MINUTES)"
      />
    </div>
  </div>
</template>
