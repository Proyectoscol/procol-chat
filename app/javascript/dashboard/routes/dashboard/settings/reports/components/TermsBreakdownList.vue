<script setup>
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// state: { isLoading, terms: [{ term, mentionsCount }] } | undefined --
// undefined solo en el instante entre expandir y que toggleTerms arranque
// el fetch (ver AuditoriaCategoryReportsIndex.vue), se trata igual que
// "cargando".
defineProps({
  state: { type: Object, default: null },
});

defineEmits(['selectTerm']);

const { t } = useI18n();

const renderCount = value => (value ? value.toLocaleString() : '--');
</script>

<template>
  <div
    v-if="!state || state.isLoading"
    class="flex items-center justify-center py-3"
  >
    <Spinner :size="20" />
  </div>
  <p v-else-if="!state.terms.length" class="text-sm text-n-slate-10">
    {{ t('AUDITORIA_CATEGORY_REPORTS.TERMS_BREAKDOWN.EMPTY') }}
  </p>
  <ul v-else class="flex flex-col gap-1 max-w-xs">
    <li
      v-for="row in state.terms"
      :key="row.term"
      class="flex items-center justify-between gap-4 text-sm"
    >
      <button
        type="button"
        class="text-n-blue-text hover:underline truncate"
        @click="$emit('selectTerm', row.term)"
      >
        {{ row.term }}
      </button>
      <span class="text-n-slate-12">{{ renderCount(row.mentionsCount) }}</span>
    </li>
  </ul>
</template>
