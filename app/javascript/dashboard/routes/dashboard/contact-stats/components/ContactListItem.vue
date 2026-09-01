<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import format from 'date-fns/format';
import fromUnixTime from 'date-fns/fromUnixTime';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  contact: {
    type: Object,
    required: true,
  },
  selected: {
    type: Boolean,
    default: false,
  },
});

defineEmits(['click', 'toggleSelect']);

const { t } = useI18n();
const labels = useMapGetter('labels/getLabels');
const contactAttributes = useMapGetter('attributes/getContactAttributes');

const labelColor = title =>
  labels.value.find(label => label.title === title)?.color || '#94a3b8';

const formatDate = timestamp =>
  timestamp ? format(fromUnixTime(timestamp), 'MMM d, yyyy · h:mm a') : '';

const customAttributesList = computed(() => {
  const raw = props.contact.custom_attributes || {};
  return (contactAttributes.value || [])
    .filter(
      a => raw[a.attributeKey] !== undefined && raw[a.attributeKey] !== ''
    )
    .map(a => ({
      label: a.attributeDisplayName,
      value: String(raw[a.attributeKey]),
    }));
});
</script>

<template>
  <button
    type="button"
    class="flex items-start w-full gap-3 p-3 text-left transition-colors border rounded-lg border-n-weak hover:bg-n-alpha-1 hover:border-n-slate-6"
    @click="$emit('click')"
  >
    <input
      type="checkbox"
      class="mt-1 flex-shrink-0 rounded border-n-weak"
      :checked="selected"
      @click.stop="$emit('toggleSelect')"
    />
    <img
      v-if="contact.thumbnail"
      :src="contact.thumbnail"
      class="size-9 flex-shrink-0 rounded-full object-cover"
      alt=""
    />
    <div
      v-else
      class="flex size-9 flex-shrink-0 items-center justify-center rounded-full bg-n-slate-3 text-xs font-medium text-n-slate-11"
    >
      {{ (contact.name || '?').charAt(0).toUpperCase() }}
    </div>
    <div class="min-w-0 flex-1">
      <div class="flex flex-wrap items-baseline gap-x-2">
        <p class="truncate text-sm font-medium text-n-slate-12">
          {{ contact.name || t('CONTACT_STATS.DRAWER.NO_NAME') }}
        </p>
        <p class="truncate text-xs text-n-slate-11">
          {{ contact.phone_number || contact.email || '—' }}
        </p>
        <p class="text-xs text-n-slate-10">
          {{ formatDate(contact.created_at) }}
        </p>
      </div>
      <div
        v-if="contact.labels?.length || customAttributesList.length"
        class="mt-1.5 flex flex-wrap gap-1"
      >
        <span
          v-for="labelTitle in contact.labels"
          :key="labelTitle"
          class="flex items-center gap-1 rounded-full bg-n-alpha-1 px-1.5 py-0.5 text-[11px] text-n-slate-11"
        >
          <span
            class="size-1.5 rounded-full"
            :style="{ backgroundColor: labelColor(labelTitle) }"
          />
          {{ labelTitle }}
        </span>
        <span
          v-for="attr in customAttributesList"
          :key="attr.label"
          class="rounded-full bg-n-alpha-1 px-1.5 py-0.5 text-[11px] text-n-slate-11"
        >
          {{ attr.label }}: {{ attr.value }}
        </span>
      </div>
    </div>
  </button>
</template>
