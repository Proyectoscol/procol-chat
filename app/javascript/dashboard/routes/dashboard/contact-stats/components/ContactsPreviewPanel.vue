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
  customFilters: { type: Object, default: () => ({}) },
  inboxId: { type: String, default: '' },
  labelTitles: { type: Array, default: () => [] },
  hourOfDay: { type: Number, default: null },
  hourFilterLabel: { type: String, default: '' },
  selectedContactIds: { type: Array, default: () => [] },
});

const emit = defineEmits(['clearHourFilter', 'update:selectedContactIds']);

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
    customFilters: props.customFilters,
    inboxId: props.inboxId,
    labelTitles: props.labelTitles,
    hourOfDay: props.hourOfDay,
    contactIds: props.selectedContactIds,
  });
};

watch(
  () => [
    props.since,
    props.until,
    props.filters,
    props.customFilters,
    props.inboxId,
    props.labelTitles,
    props.hourOfDay,
    props.selectedContactIds,
  ],
  fetchContacts,
  { deep: true }
);

onMounted(fetchContacts);

const toggleContactSelection = contactId => {
  const updated = props.selectedContactIds.includes(contactId)
    ? props.selectedContactIds.filter(id => id !== contactId)
    : [...props.selectedContactIds, contactId];
  emit('update:selectedContactIds', updated);
};
</script>

<template>
  <div
    class="flex flex-col h-full rounded-xl border border-n-weak bg-n-solid-1 p-4"
  >
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
      class="flex items-center justify-center flex-1 py-10 text-xs text-n-slate-10"
    >
      <Spinner />
    </div>
    <div
      v-else-if="hasError"
      class="flex items-center justify-center flex-1 py-10 text-xs text-n-ruby-11"
    >
      {{ t('CONTACT_STATS.DRAWER.ERROR') }}
    </div>
    <div
      v-else-if="!hasRecords"
      class="flex items-center justify-center flex-1 py-10 text-xs text-n-slate-10"
    >
      {{ t('CONTACT_STATS.EMPTY_STATE') }}
    </div>
    <div v-else class="flex flex-col flex-1 min-h-0">
      <div class="flex flex-col flex-1 gap-2 overflow-y-auto min-h-0">
        <ContactListItem
          v-for="contact in records"
          :key="contact.id"
          :contact="contact"
          :selected="selectedContactIds.includes(contact.id)"
          @click="openContactModal(contact)"
          @toggle-select="toggleContactSelection(contact.id)"
        />
      </div>

      <Button
        v-if="hasMore"
        faded
        slate
        size="sm"
        class="mx-auto mt-2 flex-shrink-0"
        :label="t('CONTACT_STATS.DRAWER.LOAD_MORE')"
        :is-loading="isFetchingMore"
        @click="loadMore"
      />
    </div>

    <KanbanContactDetailModal
      ref="modalRef"
      :contact="selectedContact"
      open-in-new-tab
      @close="selectedContact = null"
    />
  </div>
</template>
