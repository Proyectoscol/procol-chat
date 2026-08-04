<script setup>
import { ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ContactAPI from 'dashboard/api/contacts';
import { useReportDrilldown } from '../../settings/reports/composables/useReportDrilldown';
import KanbanContactDetailModal from '../../kanban/components/KanbanContactDetailModal.vue';
import ContactListItem from './ContactListItem.vue';

const props = defineProps({
  since: { type: Number, default: null },
  until: { type: Number, default: null },
  filters: { type: Object, default: () => ({}) },
  inboxId: { type: String, default: '' },
  labelTitles: { type: Array, default: () => [] },
  hourOfDay: { type: Number, default: null },
  dayFilterLabel: { type: String, default: '' },
  hourFilterLabel: { type: String, default: '' },
});

const emit = defineEmits(['clearDayFilter', 'clearHourFilter']);

const { t } = useI18n();

const {
  records,
  meta,
  isFetching,
  isFetchingMore,
  hasError,
  hasRecords,
  hasMore,
  open: openContacts,
  loadMore,
} = useReportDrilldown(params => ContactAPI.leadStatsContacts(params));

const modalRef = ref(null);
const selectedContact = ref(null);

const openContactModal = async contact => {
  selectedContact.value = contact;
  modalRef.value?.open();
};

const fetchContacts = () => {
  openContacts({
    since: props.since,
    until: props.until,
    filters: props.filters,
    inboxId: props.inboxId,
    labelTitles: props.labelTitles,
    hourOfDay: props.hourOfDay,
  });
};

watch(
  () => [
    props.since,
    props.until,
    props.filters,
    props.inboxId,
    props.labelTitles,
    props.hourOfDay,
  ],
  fetchContacts,
  { deep: true }
);

onMounted(fetchContacts);
</script>

<template>
  <div class="flex flex-col rounded-xl border border-n-weak bg-n-solid-1 p-4">
    <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
      <div>
        <h3 class="text-sm font-medium text-n-slate-12">
          {{ t('CONTACT_STATS.PREVIEW.TITLE') }}
        </h3>
        <p class="text-xs text-n-slate-10">
          {{
            t('CONTACT_STATS.PREVIEW.TOTAL', { count: meta.total_count || 0 })
          }}
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-1.5">
        <button
          v-if="dayFilterLabel"
          type="button"
          class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-brand/10 text-n-brand hover:bg-n-brand/20"
          @click="emit('clearDayFilter')"
        >
          {{ dayFilterLabel }}
          <span class="i-lucide-x size-3" />
        </button>
        <button
          v-if="hourFilterLabel"
          type="button"
          class="flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-brand/10 text-n-brand hover:bg-n-brand/20"
          @click="emit('clearHourFilter')"
        >
          {{ hourFilterLabel }}
          <span class="i-lucide-x size-3" />
        </button>
      </div>
    </div>

    <div
      v-if="isFetching"
      class="flex items-center justify-center py-10 text-xs text-n-slate-10"
    >
      <Spinner />
    </div>
    <div
      v-else-if="hasError"
      class="flex items-center justify-center py-10 text-xs text-n-ruby-11"
    >
      {{ t('CONTACT_STATS.DRAWER.ERROR') }}
    </div>
    <div
      v-else-if="!hasRecords"
      class="flex items-center justify-center py-10 text-xs text-n-slate-10"
    >
      {{ t('CONTACT_STATS.EMPTY_STATE') }}
    </div>
    <div v-else class="flex flex-col gap-2 overflow-y-auto max-h-[32rem]">
      <ContactListItem
        v-for="contact in records"
        :key="contact.id"
        :contact="contact"
        @click="openContactModal(contact)"
      />

      <Button
        v-if="hasMore"
        faded
        slate
        size="sm"
        class="mx-auto mt-2"
        :label="t('CONTACT_STATS.DRAWER.LOAD_MORE')"
        :is-loading="isFetchingMore"
        @click="loadMore"
      />
    </div>

    <KanbanContactDetailModal
      ref="modalRef"
      :contact="selectedContact"
      @close="selectedContact = null"
    />
  </div>
</template>
