<script setup>
import { ref, onMounted } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

defineProps({
  attributes: { type: Array, default: () => [] },
});

const emit = defineEmits(['configure']);

const store = useStore();
const { t } = useI18n();

const selected = ref(null);

onMounted(() => {
  store.dispatch('attributes/get');
});

const selectAttribute = attr => {
  selected.value = attr;
};

const confirm = () => {
  if (!selected.value) return;
  emit('configure', {
    attributeKey: selected.value.attributeKey,
    attributeName: selected.value.attributeDisplayName,
    attributeValues: selected.value.attributeValues || [],
  });
};
</script>

<template>
  <div class="flex flex-col items-center justify-center flex-1 gap-6 p-8">
    <div class="flex flex-col items-center gap-2 text-center">
      <span class="i-lucide-kanban size-10 text-n-brand" />
      <h2 class="text-xl font-semibold text-n-slate-12">
        {{ t('KANBAN.CONFIG.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11 max-w-sm">
        {{ t('KANBAN.CONFIG.DESCRIPTION') }}
      </p>
    </div>

    <div
      v-if="attributes.length === 0"
      class="text-sm text-n-slate-10 text-center max-w-sm"
    >
      {{ t('KANBAN.CONFIG.EMPTY_STATE') }}<br />
      {{ t('KANBAN.CONFIG.EMPTY_CTA') }}
    </div>

    <div v-else class="flex flex-col gap-2 w-full max-w-sm">
      <button
        v-for="attr in attributes"
        :key="attr.attributeKey"
        class="flex items-center gap-3 px-4 py-3 rounded-xl border text-left transition-all"
        :class="
          selected?.attributeKey === attr.attributeKey
            ? 'border-n-brand bg-n-brand/5 text-n-slate-12'
            : 'border-n-weak hover:border-n-slate-4 hover:bg-n-alpha-1 text-n-slate-11'
        "
        @click="selectAttribute(attr)"
      >
        <span class="i-lucide-list size-4 flex-shrink-0" />
        <div class="min-w-0 flex-1">
          <div class="text-sm font-medium truncate">
            {{ attr.attributeDisplayName }}
          </div>
          <div class="text-xs text-n-slate-10 truncate mt-0.5">
            {{ (attr.attributeValues || []).join(' · ') }}
          </div>
        </div>
        <span
          v-if="selected?.attributeKey === attr.attributeKey"
          class="i-lucide-check size-4 text-n-brand flex-shrink-0"
        />
      </button>
    </div>

    <button
      v-if="attributes.length > 0"
      :disabled="!selected"
      class="px-6 py-2 rounded-lg text-sm font-medium transition-colors"
      :class="
        selected
          ? 'bg-n-brand text-white hover:bg-n-brand/90 cursor-pointer'
          : 'bg-n-alpha-2 text-n-slate-10 cursor-not-allowed'
      "
      @click="confirm"
    >
      {{ t('KANBAN.CONFIG.CREATE_BUTTON') }}
    </button>
  </div>
</template>
