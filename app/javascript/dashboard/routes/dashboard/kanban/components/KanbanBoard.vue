<script setup>
import { ref, watch, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import ContactAPI from 'dashboard/api/contacts';
import ConversationAPI from 'dashboard/api/conversations';
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

// "conversation_labels" (not the separate, rarely-used contact-level "labels")
// matches tags applied to any of the contact's conversations — the labels
// agents actually set day-to-day from the conversation sidebar. It has no
// per-value filter needing an array of values (Contacts::FilterService
// collapses any values array down to values[0]), so "no tag" is expressed as
// one not_equal_to condition per tracked tag, ANDed together — the same
// pattern app/javascript/dashboard/helper/filterQueryGenerator.js already
// uses for multi-condition payloads.
const buildColumnConditions = col => {
  if (props.mode === 'tags') {
    if (col.isEmptyColumn) {
      return props.columnValues.map((tag, idx) => ({
        attribute_key: 'conversation_labels',
        filter_operator: 'not_equal_to',
        values: [tag],
        query_operator: idx === props.columnValues.length - 1 ? null : 'AND',
      }));
    }
    return [
      {
        attribute_key: 'conversation_labels',
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

// Contacts marked as "internal" (staff/test contacts, see Contact page toggle)
// never belong on the board — always AND in an exclusion condition after the
// column's own conditions, re-terminating the chain on it.
const buildFilterPayload = col => {
  const conditions = buildColumnConditions(col);
  const chained = conditions.map((condition, idx) =>
    idx === conditions.length - 1
      ? { ...condition, query_operator: 'AND' }
      : condition
  );
  return [
    ...chained,
    {
      attribute_key: 'internal',
      filter_operator: 'equal_to',
      values: [false],
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

// Tags mode writes to the contact's most recent conversation (matching
// where these labels are actually managed day-to-day), and also strips any
// tracked tag from older conversations that still carry one — otherwise the
// contact could keep showing up in a stale column via an older conversation.
const moveContactTags = async (contact, targetValue) => {
  const { data } = await ContactAPI.getConversations(contact.id);
  const conversations = data.payload || [];
  if (conversations.length === 0) {
    throw new Error('Contact has no conversation to tag');
  }

  const [mostRecent, ...rest] = conversations;
  const updates = rest
    .filter(conv =>
      (conv.labels || []).some(l => props.columnValues.includes(l))
    )
    .map(conv => ({
      id: conv.id,
      labels: (conv.labels || []).filter(l => !props.columnValues.includes(l)),
    }));

  const mostRecentLabels = (mostRecent.labels || []).filter(
    l => !props.columnValues.includes(l)
  );
  if (targetValue) mostRecentLabels.push(targetValue);
  updates.push({ id: mostRecent.id, labels: mostRecentLabels });

  await Promise.all(
    updates.map(u => ConversationAPI.updateLabels(u.id, u.labels))
  );
};

const onContactMoved = async ({ contact, targetValue }) => {
  try {
    if (props.mode === 'tags') {
      await moveContactTags(contact, targetValue);
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
