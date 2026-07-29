<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { picoSearch } from '@scmmishra/pico-search';
import AgentLockCard from './components/AgentLockCard.vue';

const store = useStore();
const getters = useStoreGetters();
const { t } = useI18n();

const searchQuery = ref('');

const agentList = computed(() => getters['agents/getAgents'].value);
const uiFlags = computed(() => getters['agents/getUIFlags'].value);

const filteredAgentList = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return agentList.value;
  return picoSearch(agentList.value, query, ['name', 'email']);
});

onMounted(() => {
  store.dispatch('agents/get');
});
</script>

<template>
  <div class="flex flex-col flex-1 h-full bg-n-surface-1 overflow-hidden">
    <header
      class="flex items-center gap-3 px-6 py-3 border-b border-n-weak flex-shrink-0"
    >
      <span class="i-lucide-user-lock size-5 text-n-slate-11" />
      <h1 class="text-base font-semibold text-n-slate-12 flex-1">
        {{ t('AGENT_LOCK.TITLE') }}
      </h1>

      <label
        class="flex items-center gap-2 h-8 px-2.5 rounded-lg border border-n-weak bg-n-background hover:border-n-slate-4 focus-within:ring-1 focus-within:ring-n-brand transition-colors cursor-text w-52"
      >
        <span class="i-lucide-search size-4 text-n-slate-10 flex-shrink-0" />
        <input
          v-model="searchQuery"
          type="text"
          :placeholder="t('AGENT_LOCK.SEARCH_PLACEHOLDER')"
          class="reset-base outline-none border-transparent shadow-none bg-transparent active:border-transparent active:shadow-none hover:border-transparent hover:shadow-none focus:border-transparent focus:shadow-none flex-1 text-sm text-n-slate-12 placeholder:text-n-slate-10 min-w-0"
        />
      </label>
    </header>

    <div class="flex-1 overflow-y-auto p-6">
      <span
        v-if="uiFlags.isFetching"
        class="flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
      >
        {{ t('AGENT_LOCK.LOADING') }}
      </span>
      <span
        v-else-if="!filteredAgentList.length"
        class="flex items-center justify-center py-20 text-center text-body-main !text-base text-n-slate-11"
      >
        {{
          searchQuery ? t('AGENT_LOCK.NO_RESULTS') : t('AGENT_LOCK.EMPTY_STATE')
        }}
      </span>
      <div v-else class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
        <AgentLockCard
          v-for="agent in filteredAgentList"
          :key="agent.id"
          :agent="agent"
        />
      </div>
    </div>
  </div>
</template>
