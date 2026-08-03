<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactListItem from './ContactListItem.vue';

defineProps({
  contacts: {
    type: Array,
    default: () => [],
  },
  totalCount: {
    type: Number,
    default: 0,
  },
  isFetching: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['view-all']);

const { t } = useI18n();
</script>

<template>
  <div
    class="flex h-full flex-col rounded-xl border border-n-weak bg-n-solid-1 p-4"
  >
    <div class="mb-3 flex items-center justify-between gap-2">
      <div>
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t('CONTACT_STATS.PREVIEW.TITLE') }}
        </h3>
        <p class="text-xs text-n-slate-10">
          {{ t('CONTACT_STATS.PREVIEW.TOTAL', { count: totalCount }) }}
        </p>
      </div>
      <Button
        faded
        slate
        size="sm"
        :label="t('CONTACT_STATS.PREVIEW.VIEW_ALL')"
        @click="emit('view-all')"
      />
    </div>

    <span
      v-if="isFetching"
      class="flex flex-1 items-center justify-center py-10 text-center text-xs text-n-slate-10"
    >
      {{ t('CONTACT_STATS.LOADING') }}
    </span>
    <span
      v-else-if="!contacts.length"
      class="flex flex-1 items-center justify-center py-10 text-center text-xs text-n-slate-10"
    >
      {{ t('CONTACT_STATS.EMPTY_STATE') }}
    </span>
    <div v-else class="flex flex-col gap-2 overflow-y-auto">
      <ContactListItem
        v-for="contact in contacts"
        :key="contact.id"
        :contact="contact"
      />
    </div>
  </div>
</template>
