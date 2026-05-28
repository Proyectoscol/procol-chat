<script setup>
import { ref, watch, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import ContactAPI from 'dashboard/api/contacts';
import KanbanColumn from './KanbanColumn.vue';

const props = defineProps({
  attributeKey: { type: String, required: true },
  attributeValues: { type: Array, default: () => [] },
  searchQuery: { type: String, default: '' },
});

const emit = defineEmits(['openModal']);

const store = useStore();

const forwardOpenModal = contact => emit('openModal', contact);
const { t } = useI18n();

const columns = ref([]);
const PAGE_SIZE = 25;

const buildColumns = () => {
  columns.value = props.attributeValues.map(value => ({
    value,
    contacts: [],
    isLoading: false,
    page: 1,
    hasMore: false,
  }));
};

const fetchColumnContacts = async (colIndex, page = 1) => {
  const col = columns.value[colIndex];
  if (!col) return;
  col.isLoading = true;
  try {
    const { data } = await ContactAPI.filter(page, 'name', {
      payload: [
        {
          attribute_key: props.attributeKey,
          filter_operator: 'equal_to',
          values: [col.value],
          query_operator: null,
        },
      ],
    });
    const incoming = data.payload || [];
    col.contacts = page === 1 ? incoming : [...col.contacts, ...incoming];
    col.page = page;
    col.hasMore = incoming.length === PAGE_SIZE;
  } catch {
    // silent per-column failure
  } finally {
    col.isLoading = false;
  }
};

const fetchAll = () => {
  buildColumns();
  columns.value.forEach((_, i) => fetchColumnContacts(i));
};

const loadMore = colIndex => {
  const col = columns.value[colIndex];
  if (col && !col.isLoading && col.hasMore) {
    fetchColumnContacts(colIndex, col.page + 1);
  }
};

const onContactMoved = async ({ contact, targetValue }) => {
  // Find source column before any mutation
  const sourceCol = columns.value.find(col =>
    col.contacts.some(c => c.id === contact.id)
  );

  // Drop on same column or already moved — no-op
  if (!sourceCol || sourceCol.value === targetValue) return;

  // Optimistic update
  sourceCol.contacts = sourceCol.contacts.filter(c => c.id !== contact.id);
  const targetCol = columns.value.find(c => c.value === targetValue);
  if (targetCol && !targetCol.contacts.find(c => c.id === contact.id)) {
    targetCol.contacts.unshift(contact);
  }

  try {
    await store.dispatch('contacts/update', {
      id: contact.id,
      customAttributes: { [props.attributeKey]: targetValue },
    });
  } catch {
    // Rollback
    if (targetCol)
      targetCol.contacts = targetCol.contacts.filter(c => c.id !== contact.id);
    if (sourceCol) sourceCol.contacts = [contact, ...sourceCol.contacts];
    useAlert(t('KANBAN.ERRORS.UPDATE_FAILED'));
  }
};

watch(() => props.attributeKey, fetchAll);
onMounted(fetchAll);
</script>

<template>
  <div class="flex-1 overflow-x-auto overflow-y-hidden">
    <div
      class="flex gap-3 h-full px-6 py-4"
      :style="{
        minWidth: `${Math.max(attributeValues.length * 272 + 48, 100)}px`,
      }"
    >
      <KanbanColumn
        v-for="(col, idx) in columns"
        :key="col.value"
        :column="col"
        :search-query="searchQuery"
        @contact-moved="onContactMoved"
        @load-more="loadMore(idx)"
        @open-modal="forwardOpenModal"
      />
    </div>
  </div>
</template>
