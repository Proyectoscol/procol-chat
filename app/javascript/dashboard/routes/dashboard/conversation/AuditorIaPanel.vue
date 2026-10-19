<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { fromUnixTime, format } from 'date-fns';
import { es } from 'date-fns/locale';
import AuditoriaConversationAnalysesAPI from 'dashboard/api/auditoriaConversationAnalyses';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const POLL_INTERVAL_MS = 3000;

const { t } = useI18n();

const isLoading = ref(false);
const isAnalyzing = ref(false);
const results = ref(null);
const analyzedAt = ref(null);
const needsAnalysis = ref(false);
const fieldConfigs = ref([]);
const errorMessage = ref('');
let pollTimer = null;

const hasResults = computed(() => !!results.value);

const lastAnalyzedLabel = computed(() => {
  if (!analyzedAt.value) {
    return t('CONVERSATION_SIDEBAR.AUDITOR_IA.NEVER_ANALYZED');
  }
  const formatted = format(
    fromUnixTime(analyzedAt.value),
    "d 'de' MMMM 'de' yyyy, HH:mm",
    { locale: es }
  );
  return t('CONVERSATION_SIDEBAR.AUDITOR_IA.LAST_ANALYZED_AT', {
    time: formatted,
  });
});

const stopPolling = () => {
  clearInterval(pollTimer);
  pollTimer = null;
};

const applyResponse = response => {
  results.value = response.data.results;
  analyzedAt.value = response.data.analyzed_at;
  needsAnalysis.value = response.data.needs_analysis;
  fieldConfigs.value = response.data.field_configs || [];
  errorMessage.value = response.data.error || '';

  isAnalyzing.value = response.data.analyzing;
  if (!isAnalyzing.value) stopPolling();
};

const fetchAnalysis = async () => {
  try {
    const response = await AuditoriaConversationAnalysesAPI.getAnalysis(
      props.conversationId
    );
    applyResponse(response);
  } catch (error) {
    errorMessage.value = t('CONVERSATION_SIDEBAR.AUDITOR_IA.ERROR');
    stopPolling();
  }
};

const startPolling = () => {
  stopPolling();
  pollTimer = setInterval(fetchAnalysis, POLL_INTERVAL_MS);
};

const analyzeNow = async () => {
  isAnalyzing.value = true;
  errorMessage.value = '';
  try {
    await AuditoriaConversationAnalysesAPI.createAnalysis(props.conversationId);
    startPolling();
  } catch (error) {
    isAnalyzing.value = false;
    errorMessage.value = t('CONVERSATION_SIDEBAR.AUDITOR_IA.ERROR');
  }
};

onMounted(async () => {
  isLoading.value = true;
  await fetchAnalysis();
  isLoading.value = false;
  if (isAnalyzing.value) startPolling();
});

onUnmounted(stopPolling);
</script>

<template>
  <div class="flex flex-col gap-3 px-1 py-2">
    <div v-if="isLoading" class="flex items-center justify-center py-4">
      <Spinner />
    </div>
    <template v-else>
      <div class="flex flex-col gap-1">
        <p class="text-sm text-n-slate-11 m-0">{{ lastAnalyzedLabel }}</p>
        <p
          v-if="needsAnalysis && hasResults && !isAnalyzing"
          class="text-sm text-n-amber-12 m-0"
        >
          {{ t('CONVERSATION_SIDEBAR.AUDITOR_IA.OUTDATED_NOTICE') }}
        </p>
        <p v-if="errorMessage" class="text-sm text-n-ruby-11 m-0">
          {{ errorMessage }}
        </p>
      </div>

      <div v-if="fieldConfigs.length" class="flex flex-col gap-3">
        <div
          v-for="field in fieldConfigs"
          :key="field.key"
          class="flex flex-col gap-1"
        >
          <span class="text-sm font-medium text-n-slate-12">{{
            field.title
          }}</span>
          <p class="text-sm text-n-slate-11 whitespace-pre-wrap m-0">
            {{ (results && results[field.key]) || '—' }}
          </p>
        </div>
      </div>
      <p v-else class="text-sm text-n-slate-11 m-0">
        {{ t('CONVERSATION_SIDEBAR.AUDITOR_IA.EMPTY') }}
      </p>

      <NextButton
        :label="
          isAnalyzing
            ? t('CONVERSATION_SIDEBAR.AUDITOR_IA.ANALYZING')
            : t('CONVERSATION_SIDEBAR.AUDITOR_IA.ANALYZE_BUTTON')
        "
        :is-loading="isAnalyzing"
        :disabled="isAnalyzing"
        size="sm"
        @click="analyzeNow"
      />
    </template>
  </div>
</template>
