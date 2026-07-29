<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Avatar from 'next/avatar/Avatar.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';

const props = defineProps({
  agent: {
    type: Object,
    required: true,
  },
});

const store = useStore();
const { t } = useI18n();

const isSaving = ref(false);

const isOnline = computed({
  get: () => props.agent.availability_status === 'online',
  set: async value => {
    isSaving.value = true;
    try {
      await store.dispatch('agents/update', {
        id: props.agent.id,
        availability: value ? 'online' : 'offline',
      });
    } catch (error) {
      useAlert(t('AGENT_LOCK.STATUS_UPDATE_ERROR'));
    } finally {
      isSaving.value = false;
    }
  },
});
</script>

<template>
  <div
    class="flex flex-col gap-4 p-4 rounded-xl border transition-colors duration-200"
    :class="
      isOnline
        ? 'bg-n-teal-2 border-n-teal-6 dark:bg-n-teal-3 dark:border-n-teal-7'
        : 'bg-n-ruby-2 border-n-ruby-6 dark:bg-n-ruby-3 dark:border-n-ruby-7'
    "
  >
    <div class="flex items-center gap-3">
      <Avatar :src="agent.thumbnail" :name="agent.name" :size="48" />
      <div class="flex flex-col min-w-0 flex-1">
        <span class="text-heading-3 text-n-slate-12 truncate">
          {{ agent.name }}
        </span>
        <span class="text-body-main text-n-slate-11 truncate">
          {{ agent.email }}
        </span>
      </div>
      <div :class="{ 'opacity-60 pointer-events-none': isSaving }">
        <Switch v-model="isOnline" />
      </div>
    </div>

    <div class="flex flex-wrap gap-1.5">
      <span
        v-for="team in agent.teams"
        :key="team.id"
        class="px-2 py-0.5 rounded-md text-xs font-medium bg-n-alpha-2 text-n-slate-11"
      >
        {{ team.name }}
      </span>
      <span
        v-if="!agent.teams || !agent.teams.length"
        class="text-xs text-n-slate-10"
      >
        {{ t('AGENT_LOCK.NO_TEAMS') }}
      </span>
    </div>
  </div>
</template>
