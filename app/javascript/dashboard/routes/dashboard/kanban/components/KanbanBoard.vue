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

const store = useStore();
const { showAlert } = useAlert();
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
    if (page === 1) {
      col.contacts = incoming;
    } else {
      col.contacts = [...col.contacts, ...incoming];
    }
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
  // Remove from source columns
  columns.value.forEach(col => {
    if (col.value !== targetValue) {
      const idx = col.contacts.findIndex(c => c.id === contact.id);
      if (idx !== -1) col.contacts.splice(idx, 1);
    }
  });
  // Ensure contact is in target column
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
    showAlert(t('KANBAN.ERRORS.UPDATE_FAILED'));
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
      />
    </div>
  </div>
</template>
