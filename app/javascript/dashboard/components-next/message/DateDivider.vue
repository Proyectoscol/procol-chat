<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, isToday, isYesterday, fromUnixTime } from 'date-fns';

const props = defineProps({
  timestamp: { type: Number, required: true },
});

const { t } = useI18n();

const label = computed(() => {
  const date = fromUnixTime(props.timestamp);
  if (isToday(date)) return t('CONVERSATION.DATE_DIVIDER.TODAY');
  if (isYesterday(date)) return t('CONVERSATION.DATE_DIVIDER.YESTERDAY');
  return format(date, 'MMM d, yyyy');
});
</script>

<template>
  <div class="flex justify-center my-2" data-bubble-name="date-divider">
    <span class="px-3 py-1 rounded-lg bg-n-alpha-1 text-n-slate-11 text-sm">
      {{ label }}
    </span>
  </div>
</template>
