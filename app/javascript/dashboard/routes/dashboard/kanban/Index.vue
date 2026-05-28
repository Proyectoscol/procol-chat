<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import KanbanBoard from './components/KanbanBoard.vue';
import KanbanConfigPanel from './components/KanbanConfigPanel.vue';

const store = useStore();
const { t } = useI18n();
const accountId = useMapGetter('getCurrentAccountId');
const contactAttributes = useMapGetter('attributes/getContactAttributes');

const searchQuery = ref('');
const config = ref(null);
const showConfigPanel = ref(false);

const storageKey = computed(() => `kanban_config_v1_${accountId.value}`);

const listAttributes = computed(() =>
  (contactAttributes.value || []).filter(a => a.attributeDisplayType === 'list')
);

const isShowingBoard = computed(() => config.value && !showConfigPanel.value);

onMounted(async () => {
  await store.dispatch('attributes/get');
  const saved = localStorage.getItem(storageKey.value);
  if (saved) {
    try {
      config.value = JSON.parse(saved);
    } catch {
      config.value = null;
    }
  }
});

const onConfigure = newConfig => {
  config.value = newConfig;
  localStorage.setItem(storageKey.value, JSON.stringify(newConfig));
  showConfigPanel.value = false;
};

const openConfig = () => {
  showConfigPanel.value = true;
};
</script>

<template>
  <div class="flex flex-col flex-1 h-full bg-n-surface-1 overflow-hidden">
    <header
      class="flex items-center gap-3 px-6 py-3 border-b border-n-weak flex-shrink-0"
    >
      <span class="i-lucide-kanban size-5 text-n-slate-11" />
      <h1 class="text-base font-semibold text-n-slate-12 flex-1">
        {{ t('KANBAN.TITLE') }}
      </h1>

      <template v-if="isShowingBoard">
        <label
          class="flex items-center gap-2 h-8 px-2.5 rounded-lg border border-n-weak bg-n-background hover:border-n-slate-4 focus-within:ring-1 focus-within:ring-n-brand transition-colors cursor-text w-52"
        >
          <span class="i-lucide-search size-4 text-n-slate-10 flex-shrink-0" />
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="t('KANBAN.SEARCH_PLACEHOLDER')"
            class="flex-1 bg-transparent text-sm text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none min-w-0"
          />
        </label>

        <button
          class="flex items-center gap-1.5 h-8 px-3 text-sm rounded-lg border border-n-weak hover:bg-n-alpha-2 text-n-slate-11 transition-colors flex-shrink-0"
          @click="openConfig"
        >
          <span class="i-lucide-settings-2 size-4" />
          <span v-if="config" class="max-w-32 truncate text-xs">
            {{ config.attributeName }}
          </span>
        </button>
      </template>
    </header>

    <KanbanConfigPanel
      v-if="!isShowingBoard"
      :attributes="listAttributes"
      @configure="onConfigure"
    />

    <KanbanBoard
      v-else
      :attribute-key="config.attributeKey"
      :attribute-values="config.attributeValues"
      :search-query="searchQuery"
    />
  </div>
</template>
