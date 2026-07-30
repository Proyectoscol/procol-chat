<script setup>
import { ref, watch, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import ContactAPI from 'dashboard/api/contacts';
import KanbanColumn from './KanbanColumn.vue';

const props = defineProps({
  mode: { type: String, default: 'attribute' }, // 'attribute' | 'tags'
  attributeKey: { type: String, default: '' },
  columnValues: { type: Array, default: () => [] },
  searchQuery: { type: String, default: '' },
});

const emit = defineEmits(['openModal']);

const store = useStore();

const forwardOpenModal = contact => emit('openModal', contact);
const { t } = useI18n();

const columns = ref([]);
const PAGE_SIZE = 25;

const emptyColumnLabel = () =>
  props.mode === 'tags'
    ? t('KANBAN.COLUMN.NO_TAG')
    : t('KANBAN.COLUMN.NO_VALUE');

const buildColumns = () => {
  const valueColumns = props.columnValues.map(value => ({
    value,
    label: value,
    contacts: [],
    isLoading: false,
    page: 1,
    hasMore: false,
  }));
  columns.value = [
    {
      value: null,
      label: emptyColumnLabel(),
      isEmptyColumn: true,
      contacts: [],
      isLoading: false,
      page: 1,
      hasMore: false,
    },
    ...valueColumns,
  ];
};

// Tags mode has no per-value filter needing an array of values (rack-attack-style
// quirk in Contacts::FilterService collapses any values array down to values[0]),
// so "no tag" is expressed as one not_equal_to condition per tracked tag, ANDed
// together — the same pattern app/javascript/dashboard/helper/filterQueryGenerator.js
// already uses for multi-condition payloads.
const buildFilterPayload = col => {
  if (props.mode === 'tags') {
    if (col.isEmptyColumn) {
      return props.columnValues.map((tag, idx) => ({
        attribute_key: 'labels',
        filter_operator: 'not_equal_to',
        values: [tag],
        query_operator: idx === props.columnValues.length - 1 ? null : 'AND',
      }));
    }
    return [
      {
        attribute_key: 'labels',
        filter_operator: 'equal_to',
        values: [col.value],
        query_operator: null,
      },
    ];
  }

  if (col.isEmptyColumn) {
    return [
      {
        attribute_key: props.attributeKey,
        filter_operator: 'is_not_present',
        values: [],
        query_operator: null,
      },
    ];
  }
  return [
    {
      attribute_key: props.attributeKey,
      filter_operator: 'equal_to',
      values: [col.value],
      query_operator: null,
    },
  ];
};

const fetchColumnContacts = async (colIndex, page = 1) => {
  const col = columns.value[colIndex];
  if (!col) return;
  col.isLoading = true;
  try {
    const { data } = await ContactAPI.filter(page, 'name', {
      payload: buildFilterPayload(col),
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
  try {
    if (props.mode === 'tags') {
      await store.dispatch('contactLabels/get', contact.id);
      const current = store.getters['contactLabels/getContactLabels'](
        contact.id
      );
      const next = current
        .filter(label => !props.columnValues.includes(label))
        .concat(targetValue ? [targetValue] : []);
      await store.dispatch('contactLabels/update', {
        contactId: contact.id,
        labels: next,
      });
    } else {
      await store.dispatch('contacts/update', {
        id: contact.id,
        customAttributes: { [props.attributeKey]: targetValue },
      });
    }
  } catch {
    useAlert(t('KANBAN.ERRORS.UPDATE_FAILED'));
    fetchAll();
  }
};

watch(
  () => JSON.stringify([props.mode, props.attributeKey, props.columnValues]),
  fetchAll
);
onMounted(fetchAll);
</script>

<template>
  <div class="flex-1 overflow-x-auto overflow-y-hidden">
    <div
      class="flex gap-3 h-full px-6 py-4"
      :style="{
        minWidth: `${Math.max((columnValues.length + 1) * 272 + 48, 100)}px`,
      }"
    >
      <KanbanColumn
        v-for="(col, idx) in columns"
        :key="col.value ?? '__empty__'"
        :column="col"
        :search-query="searchQuery"
        @contact-moved="onContactMoved"
        @update-contacts="col.contacts = $event"
        @load-more="loadMore(idx)"
        @open-modal="forwardOpenModal"
      />
    </div>
  </div>
</template>
