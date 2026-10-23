<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useDebounceFn } from '@vueuse/core';
import { format, fromUnixTime } from 'date-fns';
import { es } from 'date-fns/locale';
import { useAlert } from 'dashboard/composables';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import AuditoriaAiUsageAPI from 'dashboard/api/auditoriaAiUsage';
import AuditoriaDailyJobsAPI from 'dashboard/api/auditoriaDailyJobs';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import ManualRunEstimateModal from './ManualRunEstimateModal.vue';
import PipelineProgressCard from './PipelineProgressCard.vue';

const LOGS_PER_PAGE = 25;
const MIN_COST_DEBOUNCE_MS = 400;

const { t } = useI18n();
const { accountId } = useAccount();

// Correr el pipeline a mano gasta IA de toda la cuenta -- reservado al
// administrator SIN restriccion (ver Auditoria::DailyJobsPolicy), aunque
// esta pantalla la pueda VER cualquier agent/admin restringido. Se oculta
// en vez de mostrar un boton que siempre devolveria 403.
const currentRole = useMapGetter('getCurrentRole');
const currentUserInboxRestricted = useMapGetter(
  'getCurrentUserInboxRestricted'
);
const canRunDailyJobs = computed(
  () =>
    currentRole.value === 'administrator' && !currentUserInboxRestricted.value
);

const isLoading = ref(false);
const isSaving = ref(false);
const showEstimateModal = ref(false);
const isLoadingEstimate = ref(false);
const isRunningManualJob = ref(false);
const estimate = ref(null);
const activeKind = ref(null);
const summary = ref(null);
const logs = ref([]);
const totalLogs = ref(0);
const currentPage = ref(1);
const minCost = ref('');
const sortBy = ref('created_at');
const sortDirection = ref('desc');

const columns = computed(() => [
  { key: 'created_at', label: t('AUDITORIA_AI_USAGE.LOGS_TABLE.DATE') },
  { key: 'feature', label: t('AUDITORIA_AI_USAGE.LOGS_TABLE.FEATURE') },
  { key: 'model', label: t('AUDITORIA_AI_USAGE.LOGS_TABLE.MODEL') },
  { key: 'total_tokens', label: t('AUDITORIA_AI_USAGE.LOGS_TABLE.TOKENS') },
  { key: 'cost_usd', label: t('AUDITORIA_AI_USAGE.LOGS_TABLE.COST') },
  {
    key: 'triggered_by',
    label: t('AUDITORIA_AI_USAGE.LOGS_TABLE.TRIGGERED_BY'),
  },
]);

const costLimit = ref('');
const tokenLimit = ref('');
const chatModel = ref('');
const transcriptionModel = ref('');

const formatCost = value =>
  value ? `$${Number(value).toFixed(6)}` : '$0.000000';
const formatTokens = value => (value ? Number(value).toLocaleString() : '0');
const formatTokensInOut = (promptTokens, completionTokens) =>
  `${formatTokens(promptTokens)} / ${formatTokens(completionTokens)}`;
const formatDate = unixTime =>
  format(fromUnixTime(unixTime), "d 'de' MMM yyyy, HH:mm", { locale: es });

// Cada rama llama a t() con una clave literal a proposito (regla
// no-dynamic-keys) -- el mapa resultante ya tiene los textos traducidos,
// featureLabel solo busca por el valor crudo del enum.
const featureLabels = computed(() => ({
  conversation_analysis: t('AUDITORIA_AI_USAGE.FEATURE.CONVERSATION_ANALYSIS'),
  audio_transcription: t('AUDITORIA_AI_USAGE.FEATURE.AUDIO_TRANSCRIPTION'),
  advisor_daily_rollup: t('AUDITORIA_AI_USAGE.FEATURE.ADVISOR_DAILY_ROLLUP'),
}));

const featureLabel = feature => featureLabels.value[feature] || feature;

const logLink = log => {
  if (!log.conversationId) return null;
  const params = log.messageId ? { messageId: log.messageId } : undefined;
  return frontendURL(
    conversationUrl({ id: log.conversationId, accountId: accountId.value }),
    params
  );
};

const triggeredByLabel = triggeredBy =>
  triggeredBy === 'manual'
    ? t('AUDITORIA_AI_USAGE.TRIGGERED_BY.MANUAL')
    : t('AUDITORIA_AI_USAGE.TRIGGERED_BY.BATCH');

const sortIcon = key => {
  if (sortBy.value !== key) return 'i-lucide-arrow-up-down';
  return sortDirection.value === 'asc'
    ? 'i-lucide-arrow-up'
    : 'i-lucide-arrow-down';
};

const conversationAnalysisTotals = computed(
  () => summary.value?.byFeature?.conversationAnalysis || {}
);
const audioTranscriptionTotals = computed(
  () => summary.value?.byFeature?.audioTranscription || {}
);
const advisorDailyRollupTotals = computed(
  () => summary.value?.byFeature?.advisorDailyRollup || {}
);

const fetchSummary = async () => {
  const response = await AuditoriaAiUsageAPI.getSummary();
  const data = useCamelCase(response.data, { deep: true });
  summary.value = data;
  costLimit.value = data.limits?.monthlyCostLimitUsd ?? '';
  tokenLimit.value = data.limits?.monthlyTokenLimit ?? '';
  chatModel.value = data.models?.chatModel ?? '';
  transcriptionModel.value = data.models?.transcriptionModel ?? '';
};

const fetchLogs = async page => {
  const response = await AuditoriaAiUsageAPI.getLogs(page, {
    sortBy: sortBy.value,
    sortDirection: sortDirection.value,
    minCost: minCost.value,
  });
  const data = useCamelCase(response.data, { deep: true });
  logs.value = data.logs;
  totalLogs.value = data.totalCount;
};

const toggleSort = key => {
  sortDirection.value =
    sortBy.value === key && sortDirection.value === 'desc' ? 'asc' : 'desc';
  sortBy.value = key;
  currentPage.value = 1;
  fetchLogs(1);
};

const onMinCostChange = useDebounceFn(() => {
  currentPage.value = 1;
  fetchLogs(1);
}, MIN_COST_DEBOUNCE_MS);

watch(minCost, onMinCostChange);

const fetchAll = async () => {
  isLoading.value = true;
  try {
    await Promise.all([fetchSummary(), fetchLogs(currentPage.value)]);
  } catch (error) {
    useAlert(t('AUDITORIA_AI_USAGE.FETCH_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const onPageChange = async page => {
  currentPage.value = page;
  await fetchLogs(page);
};

const saveSettings = async () => {
  isSaving.value = true;
  try {
    await AuditoriaAiUsageAPI.updateSettings({
      auditoria_ai_monthly_cost_limit_usd: costLimit.value || null,
      auditoria_ai_monthly_token_limit: tokenLimit.value || null,
      auditoria_chat_model: chatModel.value || null,
      auditoria_transcription_model: transcriptionModel.value || null,
    });
    useAlert(t('AUDITORIA_AI_USAGE.SAVE_SUCCESS'));
    await fetchSummary();
  } catch (error) {
    useAlert(t('AUDITORIA_AI_USAGE.SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};

// Las 3 corridas (analisis, rollup, backlog) pasan por el mismo flujo:
// estimado -> confirmar -> encolar -- el usuario aprueba explicitamente el
// gasto proyectado antes de que esto encole nada. El progreso en vivo
// (PipelineProgressCard) se auto-restaura solo con pollear, no depende de
// este flujo de confirmacion.
const openEstimateModal = async kind => {
  activeKind.value = kind;
  showEstimateModal.value = true;
  isLoadingEstimate.value = true;
  try {
    const { data } = await AuditoriaDailyJobsAPI.getEstimate(kind);
    estimate.value = useCamelCase(data, { deep: true });
  } catch (error) {
    useAlert(t('AUDITORIA_AI_USAGE.ESTIMATE_ERROR'));
    showEstimateModal.value = false;
  } finally {
    isLoadingEstimate.value = false;
  }
};

const closeEstimateModal = () => {
  showEstimateModal.value = false;
  estimate.value = null;
  activeKind.value = null;
};

// Cada rama llama a un metodo literal del API client a proposito, en vez de
// armar el nombre del metodo en runtime -- mismo espiritu que featureLabels
// de arriba, pero para side-effects en vez de traducciones.
const runManualJob = kind => {
  if (kind === 'conversation_analysis') {
    return AuditoriaDailyJobsAPI.runConversationAnalysis();
  }
  if (kind === 'advisor_rollup') {
    return AuditoriaDailyJobsAPI.runAdvisorRollup();
  }
  return AuditoriaDailyJobsAPI.runFullBacklog();
};

const confirmManualRun = async () => {
  isRunningManualJob.value = true;
  try {
    await runManualJob(activeKind.value);
    useAlert(t('AUDITORIA_AI_USAGE.RUN_QUEUED_SUCCESS'));
    closeEstimateModal();
  } catch (error) {
    useAlert(t('AUDITORIA_AI_USAGE.RUN_QUEUED_ERROR'));
  } finally {
    isRunningManualJob.value = false;
  }
};

onMounted(fetchAll);
</script>

<template>
  <div class="flex flex-col gap-6 max-w-4xl">
    <div v-if="isLoading" class="flex items-center justify-center py-8">
      <Spinner />
    </div>
    <template v-else>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div
          class="flex flex-col gap-1 p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
        >
          <span class="text-sm text-n-slate-11">{{
            t('AUDITORIA_AI_USAGE.TOTAL_COST_THIS_MONTH')
          }}</span>
          <span class="text-2xl text-n-slate-12">{{
            formatCost(summary?.totals?.costUsd)
          }}</span>
          <span
            v-if="summary?.limits?.monthlyCostLimitUsd"
            class="text-xs text-n-slate-10"
          >
            {{
              t('AUDITORIA_AI_USAGE.LIMIT_OF', {
                limit: formatCost(summary.limits.monthlyCostLimitUsd),
              })
            }}
          </span>
        </div>
        <div
          class="flex flex-col gap-1 p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
        >
          <span class="text-sm text-n-slate-11">{{
            t('AUDITORIA_AI_USAGE.TOTAL_TOKENS_THIS_MONTH')
          }}</span>
          <span class="text-2xl text-n-slate-12">{{
            formatTokens(summary?.totals?.totalTokens)
          }}</span>
          <span
            v-if="summary?.limits?.monthlyTokenLimit"
            class="text-xs text-n-slate-10"
          >
            {{
              t('AUDITORIA_AI_USAGE.LIMIT_OF', {
                limit: formatTokens(summary.limits.monthlyTokenLimit),
              })
            }}
          </span>
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div
          class="flex flex-col gap-1 p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
        >
          <span class="text-sm font-medium text-n-slate-12">{{
            t('AUDITORIA_AI_USAGE.FEATURE.CONVERSATION_ANALYSIS')
          }}</span>
          <span class="text-sm text-n-slate-11">{{
            t('AUDITORIA_AI_USAGE.FEATURE_SUMMARY', {
              cost: formatCost(conversationAnalysisTotals.costUsd),
              tokens: formatTokens(conversationAnalysisTotals.totalTokens),
            })
          }}</span>
        </div>
        <div
          class="flex flex-col gap-1 p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
        >
          <span class="text-sm font-medium text-n-slate-12">{{
            t('AUDITORIA_AI_USAGE.FEATURE.AUDIO_TRANSCRIPTION')
          }}</span>
          <span class="text-sm text-n-slate-11">{{
            t('AUDITORIA_AI_USAGE.FEATURE_SUMMARY', {
              cost: formatCost(audioTranscriptionTotals.costUsd),
              tokens: formatTokens(audioTranscriptionTotals.totalTokens),
            })
          }}</span>
        </div>
        <div
          class="flex flex-col gap-1 p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
        >
          <span class="text-sm font-medium text-n-slate-12">{{
            t('AUDITORIA_AI_USAGE.FEATURE.ADVISOR_DAILY_ROLLUP')
          }}</span>
          <span class="text-sm text-n-slate-11">{{
            t('AUDITORIA_AI_USAGE.FEATURE_SUMMARY', {
              cost: formatCost(advisorDailyRollupTotals.costUsd),
              tokens: formatTokens(advisorDailyRollupTotals.totalTokens),
            })
          }}</span>
        </div>
      </div>

      <div
        v-if="canRunDailyJobs"
        class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
      >
        <span class="text-sm font-medium text-n-slate-12">{{
          t('AUDITORIA_AI_USAGE.MANUAL_RUN_HEADER')
        }}</span>
        <p class="text-xs text-n-slate-11">
          {{ t('AUDITORIA_AI_USAGE.MANUAL_RUN_HINT') }}
        </p>

        <div class="flex flex-col gap-3">
          <div class="flex items-center justify-between gap-3 flex-wrap">
            <div class="flex flex-col gap-0.5 max-w-sm">
              <span class="text-sm text-n-slate-12">{{
                t('AUDITORIA_AI_USAGE.RUN_CONVERSATION_ANALYSIS_BUTTON')
              }}</span>
              <span class="text-xs text-n-slate-10">{{
                t('AUDITORIA_AI_USAGE.RUN_CONVERSATION_ANALYSIS_DESCRIPTION')
              }}</span>
            </div>
            <Button
              :label="t('AUDITORIA_AI_USAGE.RUN_CONVERSATION_ANALYSIS_BUTTON')"
              size="sm"
              faded
              slate
              @click="openEstimateModal('conversation_analysis')"
            />
          </div>
          <PipelineProgressCard kind="conversation_analysis" />

          <div class="flex items-center justify-between gap-3 flex-wrap">
            <div class="flex flex-col gap-0.5 max-w-sm">
              <span class="text-sm text-n-slate-12">{{
                t('AUDITORIA_AI_USAGE.RUN_ADVISOR_ROLLUP_BUTTON')
              }}</span>
              <span class="text-xs text-n-slate-10">{{
                t('AUDITORIA_AI_USAGE.RUN_ADVISOR_ROLLUP_DESCRIPTION')
              }}</span>
            </div>
            <Button
              :label="t('AUDITORIA_AI_USAGE.RUN_ADVISOR_ROLLUP_BUTTON')"
              size="sm"
              faded
              slate
              @click="openEstimateModal('advisor_rollup')"
            />
          </div>
          <PipelineProgressCard kind="advisor_rollup" />

          <div class="flex items-center justify-between gap-3 flex-wrap">
            <div class="flex flex-col gap-0.5 max-w-sm">
              <span class="text-sm text-n-slate-12">{{
                t('AUDITORIA_AI_USAGE.RUN_BACKLOG_BUTTON')
              }}</span>
              <span class="text-xs text-n-slate-10">{{
                t('AUDITORIA_AI_USAGE.RUN_BACKLOG_DESCRIPTION')
              }}</span>
            </div>
            <Button
              :label="t('AUDITORIA_AI_USAGE.RUN_BACKLOG_BUTTON')"
              size="sm"
              faded
              slate
              @click="openEstimateModal('backlog')"
            />
          </div>
          <PipelineProgressCard kind="backlog" />
        </div>
      </div>

      <div
        class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
      >
        <span class="text-sm font-medium text-n-slate-12">{{
          t('AUDITORIA_AI_USAGE.SETTINGS_HEADER')
        }}</span>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
          <Input
            id="auditoria-cost-limit"
            v-model="costLimit"
            type="number"
            :label="t('AUDITORIA_AI_USAGE.COST_LIMIT_LABEL')"
            :placeholder="t('AUDITORIA_AI_USAGE.NO_LIMIT_PLACEHOLDER')"
          />
          <Input
            id="auditoria-token-limit"
            v-model="tokenLimit"
            type="number"
            :label="t('AUDITORIA_AI_USAGE.TOKEN_LIMIT_LABEL')"
            :placeholder="t('AUDITORIA_AI_USAGE.NO_LIMIT_PLACEHOLDER')"
          />
          <Input
            id="auditoria-chat-model"
            v-model="chatModel"
            :label="t('AUDITORIA_AI_USAGE.CHAT_MODEL_LABEL')"
            placeholder="gpt-4.1-mini"
          />
          <Input
            id="auditoria-transcription-model"
            v-model="transcriptionModel"
            :label="t('AUDITORIA_AI_USAGE.TRANSCRIPTION_MODEL_LABEL')"
            placeholder="gpt-4o-mini-transcribe"
          />
        </div>
        <Button
          :label="t('AUDITORIA_AI_USAGE.SAVE_BUTTON')"
          size="sm"
          class="self-end"
          :is-loading="isSaving"
          @click="saveSettings"
        />
      </div>

      <div class="flex flex-col gap-3">
        <div class="flex items-center justify-between gap-3 flex-wrap">
          <span class="text-sm font-medium text-n-slate-12">{{
            t('AUDITORIA_AI_USAGE.LOGS_HEADER')
          }}</span>
          <Input
            id="auditoria-min-cost"
            v-model="minCost"
            type="number"
            class="!mb-0 w-40"
            :placeholder="t('AUDITORIA_AI_USAGE.MIN_COST_LABEL')"
          />
        </div>
        <div
          class="rounded-xl outline outline-1 outline-n-weak overflow-hidden"
        >
          <BaseTable
            :headers="columns"
            :items="logs"
            :no-data-message="t('AUDITORIA_AI_USAGE.LOGS_EMPTY')"
          >
            <template
              v-for="(column, index) in columns"
              #[`header-${index}`]="{ header }"
              :key="column.key"
            >
              <button
                type="button"
                class="flex items-center gap-1 hover:text-n-slate-12"
                @click="toggleSort(header.key)"
              >
                {{ header.label }}
                <span :class="sortIcon(header.key)" class="size-3.5" />
              </button>
            </template>
            <template #row="{ items }">
              <BaseTableRow v-for="log in items" :key="log.id" :item="log">
                <BaseTableCell class="whitespace-nowrap">
                  {{ formatDate(log.createdAt) }}
                </BaseTableCell>
                <BaseTableCell class="whitespace-nowrap">
                  <router-link
                    v-if="logLink(log)"
                    :to="logLink(log)"
                    class="text-n-brand hover:underline"
                  >
                    {{ featureLabel(log.feature) }}
                  </router-link>
                  <span v-else>{{ featureLabel(log.feature) }}</span>
                </BaseTableCell>
                <BaseTableCell class="whitespace-nowrap">
                  {{ log.model }}
                </BaseTableCell>
                <BaseTableCell class="whitespace-nowrap">
                  {{
                    formatTokensInOut(log.promptTokens, log.completionTokens)
                  }}
                </BaseTableCell>
                <BaseTableCell class="whitespace-nowrap">
                  {{ formatCost(log.costUsd) }}
                </BaseTableCell>
                <BaseTableCell class="whitespace-nowrap">
                  {{ triggeredByLabel(log.triggeredBy) }}
                </BaseTableCell>
              </BaseTableRow>
            </template>
          </BaseTable>
        </div>
        <PaginationFooter
          :current-page="currentPage"
          :total-items="totalLogs"
          :items-per-page="LOGS_PER_PAGE"
          @update:current-page="onPageChange"
        />
      </div>
    </template>

    <woot-modal v-model:show="showEstimateModal" :on-close="closeEstimateModal">
      <ManualRunEstimateModal
        v-if="activeKind"
        :kind="activeKind"
        :estimate="estimate"
        :is-loading-estimate="isLoadingEstimate"
        :is-running="isRunningManualJob"
        @confirm="confirmManualRun"
        @close="closeEstimateModal"
      />
    </woot-modal>
  </div>
</template>
