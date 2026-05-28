<script setup>
import { ref, computed, watch } from 'vue';
import Draggable from 'vuedraggable';
import { useI18n } from 'vue-i18n';
import KanbanCard from './KanbanCard.vue';

const props = defineProps({
  column: { type: Object, required: true },
  searchQuery: { type: String, default: '' },
});

const emit = defineEmits(['contactMoved', 'loadMore', 'openModal']);

const { t } = useI18n();

const isDragging = ref(false);

// Local copy — avoids mutating prop; re-syncs when parent appends (loadMore)
const localContacts = ref([]);
watch(
  () => props.column.contacts,
  val => {
    localContacts.value = [...val];
  },
  { immediate: true }
);

const filteredContacts = computed(() => {
  const q = props.searchQuery.toLowerCase();
  return localContacts.value.filter(
    c =>
      c.name?.toLowerCase().includes(q) ||
      c.phone_number?.includes(q) ||
      c.email?.toLowerCase().includes(q)
  );
});

const onDragStart = () => {
  isDragging.value = true;
};

const onDragEnd = () => {
  isDragging.value = false;
};

const onChange = event => {
  if (event.added) {
    emit('contactMoved', {
      contact: event.added.element,
      targetValue: props.column.value,
    });
  }
};
</script>

<template>
  <div
    class="flex flex-col w-64 flex-shrink-0 rounded-xl bg-n-alpha-1 border border-n-weak overflow-hidden h-[calc(100vh-130px)]"
  >
    <div
      class="flex items-center justify-between px-3 py-2.5 border-b border-n-weak flex-shrink-0 bg-n-alpha-1"
    >
      <h3 class="text-sm font-semibold text-n-slate-12 truncate">
        {{ column.value }}
      </h3>
      <span
        class="text-xs font-medium text-n-slate-10 bg-n-background rounded-full px-2 py-0.5 flex-shrink-0 border border-n-weak"
      >
        {{ localContacts.length }}
      </span>
    </div>

    <div class="flex-1 overflow-y-auto p-2 min-h-0">
      <div
        v-if="column.isLoading && localContacts.length === 0"
        class="flex items-center justify-center py-8"
      >
        <span class="i-lucide-loader-2 size-5 text-n-slate-10 animate-spin" />
      </div>

      <!-- Static list when search is active (no drag) -->
      <template v-else-if="searchQuery">
        <div class="flex flex-col gap-2">
          <KanbanCard
            v-for="contact in filteredContacts"
            :key="contact.id"
            :contact="contact"
            :is-dragging="false"
            @open-modal="$emit('openModal', $event)"
          />
        </div>
      </template>

      <!-- Draggable list when no search -->
      <Draggable
        v-else
        v-model="localContacts"
        :group="{ name: 'kanban', pull: true, put: true }"
        item-key="id"
        :delay="250"
        :delay-on-touch-only="false"
        :animation="200"
        class="flex flex-col gap-2 min-h-8"
        ghost-class="opacity-30"
        chosen-class="shadow-lg"
        @change="onChange"
        @start="onDragStart"
        @end="onDragEnd"
      >
        <template #item="{ element }">
          <KanbanCard
            :contact="element"
            :is-dragging="isDragging"
            @open-modal="$emit('openModal', $event)"
          />
        </template>
      </Draggable>

      <div
        v-if="localContacts.length === 0 && !column.isLoading"
        class="flex items-center justify-center py-8 text-xs text-n-slate-10"
      >
        {{ t('KANBAN.COLUMN.EMPTY') }}
      </div>

      <button
        v-if="column.hasMore && !column.isLoading"
        class="w-full text-xs text-n-slate-10 hover:text-n-slate-12 py-2 rounded-lg hover:bg-n-alpha-2 transition-colors mt-1"
        @click="$emit('loadMore')"
      >
        {{ t('KANBAN.COLUMN.LOAD_MORE') }}
      </button>

      <div
        v-if="column.isLoading && localContacts.length > 0"
        class="flex justify-center py-2"
      >
        <span class="i-lucide-loader-2 size-4 text-n-slate-10 animate-spin" />
      </div>
    </div>
  </div>
</template>
