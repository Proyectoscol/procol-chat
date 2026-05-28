<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  contact: { type: Object, required: true },
  isDragging: { type: Boolean, default: false },
});

const emit = defineEmits(['openModal']);

const { t } = useI18n();

const initials = computed(() => {
  const name = props.contact.name || '';
  return (
    name
      .split(' ')
      .slice(0, 2)
      .map(n => n[0])
      .join('')
      .toUpperCase() || '?'
  );
});

const hasNotes = computed(
  () => props.contact.additional_attributes?.notes_count > 0
);

const openModal = () => {
  if (props.isDragging) return;
  emit('openModal', props.contact);
};
</script>

<template>
  <div
    class="bg-n-background rounded-lg border border-n-weak p-3 cursor-pointer hover:border-n-slate-4 hover:shadow-sm transition-all select-none group"
    :class="{ 'cursor-grab active:cursor-grabbing': !isDragging }"
    @click.stop="openModal"
  >
    <div class="flex items-start gap-2.5">
      <div class="flex-shrink-0">
        <img
          v-if="contact.thumbnail"
          :src="contact.thumbnail"
          :alt="contact.name"
          class="size-8 rounded-full object-cover"
        />
        <div
          v-else
          class="size-8 rounded-full bg-n-brand/10 text-n-brand text-xs font-semibold flex items-center justify-center"
        >
          {{ initials }}
        </div>
      </div>

      <div class="min-w-0 flex-1">
        <p class="text-sm font-medium text-n-slate-12 truncate leading-tight">
          {{ contact.name || t('KANBAN.CARD.NO_NAME') }}
        </p>
        <p
          v-if="contact.phone_number"
          class="text-xs text-n-slate-10 truncate mt-0.5"
        >
          {{ contact.phone_number }}
        </p>
        <p
          v-else-if="contact.email"
          class="text-xs text-n-slate-10 truncate mt-0.5"
        >
          {{ contact.email }}
        </p>
      </div>

      <div class="flex items-center gap-1 flex-shrink-0">
        <span
          v-if="hasNotes"
          class="i-lucide-sticky-note size-3 text-n-slate-10 flex-shrink-0"
          :title="t('KANBAN.CARD.HAS_NOTES')"
        />
        <span
          class="i-lucide-chevron-right size-3.5 text-n-slate-10 opacity-0 group-hover:opacity-100 transition-opacity"
        />
      </div>
    </div>
  </div>
</template>
