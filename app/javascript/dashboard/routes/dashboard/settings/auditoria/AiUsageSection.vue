<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, fromUnixTime } from 'date-fns';
import { es } from 'date-fns/locale';
import { useAlert } from 'dashboard/composables';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import { useAccount } from 'dashboard/composables/useAccount';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import AuditoriaAiUsageAPI from 'dashboard/api/auditoriaAiUsage';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

const LOGS_PER_PAGE = 25;

const { t } = useI18n();
const { accountId } = useAccount();

const isLoading = ref(false);
const isSaving = ref(false);
const summary = ref(null);
const logs = ref([]);
const totalLogs = ref(0);
const currentPage = ref(1);

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

const featureLabel = feature =>
  feature === 'conversation_analysis'
    ? t('AUDITORIA_AI_USAGE.FEATURE.CONVERSATION_ANALYSIS')
    : t('AUDITORIA_AI_USAGE.FEATURE.AUDIO_TRANSCRIPTION');

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

const conversationAnalysisTotals = computed(
  () => summary.value?.byFeature?.conversationAnalysis || {}
);
const audioTranscriptionTotals = computed(
  () => summary.value?.byFeature?.audioTranscription || {}
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
  const response = await AuditoriaAiUsageAPI.getLogs(page);
  const data = useCamelCase(response.data, { deep: true });
  logs.value = data.logs;
  totalLogs.value = data.totalCount;
};

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

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
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
        <span class="text-sm font-medium text-n-slate-12">{{
          t('AUDITORIA_AI_USAGE.LOGS_HEADER')
        }}</span>
        <div
          class="overflow-x-auto rounded-xl outline outline-1 outline-n-weak"
        >
          <table class="w-full text-sm">
            <thead>
              <tr class="bg-n-solid-2 text-left text-n-slate-11">
                <th class="px-3 py-2">
                  {{ t('AUDITORIA_AI_USAGE.LOGS_TABLE.DATE') }}
                </th>
                <th class="px-3 py-2">
                  {{ t('AUDITORIA_AI_USAGE.LOGS_TABLE.FEATURE') }}
                </th>
                <th class="px-3 py-2">
                  {{ t('AUDITORIA_AI_USAGE.LOGS_TABLE.MODEL') }}
                </th>
                <th class="px-3 py-2">
                  {{ t('AUDITORIA_AI_USAGE.LOGS_TABLE.TOKENS') }}
                </th>
                <th class="px-3 py-2">
                  {{ t('AUDITORIA_AI_USAGE.LOGS_TABLE.COST') }}
                </th>
                <th class="px-3 py-2">
                  {{ t('AUDITORIA_AI_USAGE.LOGS_TABLE.TRIGGERED_BY') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="log in logs"
                :key="log.id"
                class="border-t border-n-weak text-n-slate-12"
              >
                <td class="px-3 py-2 whitespace-nowrap">
                  {{ formatDate(log.createdAt) }}
                </td>
                <td class="px-3 py-2 whitespace-nowrap">
                  <router-link
                    v-if="logLink(log)"
                    :to="logLink(log)"
                    class="text-n-brand hover:underline"
                  >
                    {{ featureLabel(log.feature) }}
                  </router-link>
                  <span v-else>{{ featureLabel(log.feature) }}</span>
                </td>
                <td class="px-3 py-2 whitespace-nowrap">{{ log.model }}</td>
                <td class="px-3 py-2 whitespace-nowrap">
                  {{
                    formatTokensInOut(log.promptTokens, log.completionTokens)
                  }}
                </td>
                <td class="px-3 py-2 whitespace-nowrap">
                  {{ formatCost(log.costUsd) }}
                </td>
                <td class="px-3 py-2 whitespace-nowrap">
                  {{ triggeredByLabel(log.triggeredBy) }}
                </td>
              </tr>
              <tr v-if="!logs.length">
                <td colspan="6" class="px-3 py-6 text-center text-n-slate-11">
                  {{ t('AUDITORIA_AI_USAGE.LOGS_EMPTY') }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <PaginationFooter
          v-if="totalLogs > LOGS_PER_PAGE"
          :current-page="currentPage"
          :total-items="totalLogs"
          :items-per-page="LOGS_PER_PAGE"
          @update:current-page="onPageChange"
        />
      </div>
    </template>
  </div>
</template>
