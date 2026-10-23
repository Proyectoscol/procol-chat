<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  kind: {
    type: String,
    required: true,
    validator: value =>
      ['conversation_analysis', 'advisor_rollup', 'backlog'].includes(value),
  },
  estimate: { type: Object, default: null },
  isLoadingEstimate: { type: Boolean, default: false },
  isRunning: { type: Boolean, default: false },
});
const emit = defineEmits(['confirm', 'close']);

const { t } = useI18n();

// Cada rama llama a t() con una clave literal a proposito (regla
// no-dynamic-keys) -- el mapa resultante ya tiene los textos traducidos,
// el lookup por kind pasa por el objeto, nunca por una clave armada en
// runtime.
const titleByKind = computed(() => ({
  conversation_analysis: t(
    'AUDITORIA_AI_USAGE.ESTIMATE_MODAL_TITLE_CONVERSATION_ANALYSIS'
  ),
  advisor_rollup: t('AUDITORIA_AI_USAGE.ESTIMATE_MODAL_TITLE_ADVISOR_ROLLUP'),
  backlog: t('AUDITORIA_AI_USAGE.ESTIMATE_MODAL_TITLE_BACKLOG'),
}));
const emptyByKind = computed(() => ({
  conversation_analysis: t(
    'AUDITORIA_AI_USAGE.ESTIMATE_MODAL_EMPTY_CONVERSATION_ANALYSIS'
  ),
  advisor_rollup: t('AUDITORIA_AI_USAGE.ESTIMATE_MODAL_EMPTY_ADVISOR_ROLLUP'),
  backlog: t('AUDITORIA_AI_USAGE.ESTIMATE_MODAL_EMPTY_BACKLOG'),
}));
const candidatesLabelByKind = computed(() => ({
  conversation_analysis: count =>
    t('AUDITORIA_AI_USAGE.ESTIMATE_MODAL_CANDIDATES_CONVERSATION_ANALYSIS', {
      count,
    }),
  advisor_rollup: count =>
    t('AUDITORIA_AI_USAGE.ESTIMATE_MODAL_CANDIDATES_ADVISOR_ROLLUP', {
      count,
    }),
  backlog: count =>
    t('AUDITORIA_AI_USAGE.ESTIMATE_MODAL_CANDIDATES_BACKLOG', { count }),
}));

const title = computed(() => titleByKind.value[props.kind]);
const emptyMessage = computed(() => emptyByKind.value[props.kind]);
const candidatesLabel = computed(() =>
  candidatesLabelByKind.value[props.kind](props.estimate?.candidateCount ?? 0)
);

const formatCost = value =>
  value ? `$${Number(value).toFixed(6)}` : '$0.000000';
const formatTokens = value => (value ? Number(value).toLocaleString() : '0');

const onConfirm = () => emit('confirm');
const onClose = () => emit('close');
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header :header-title="title" />
    <div class="flex flex-col gap-3 px-4 pb-4 w-full !self-stretch">
      <div
        v-if="isLoadingEstimate"
        class="flex items-center justify-center py-8"
      >
        <Spinner />
      </div>
      <template v-else-if="estimate">
        <p v-if="!estimate.candidateCount" class="text-sm text-n-slate-11">
          {{ emptyMessage }}
        </p>
        <template v-else>
          <p class="text-sm text-n-slate-12">
            {{ candidatesLabel }}
          </p>
          <p
            v-if="estimate.pendingAudioMessagesCount"
            class="text-sm text-n-slate-11"
          >
            {{
              t('AUDITORIA_AI_USAGE.BACKLOG_MODAL_PENDING_AUDIO', {
                count: estimate.pendingAudioMessagesCount,
              })
            }}
          </p>
          <p
            v-if="estimate.estimatedInputTokens"
            class="text-sm text-n-slate-11"
          >
            {{
              t('AUDITORIA_AI_USAGE.BACKLOG_MODAL_ESTIMATED_TOKENS', {
                tokens: formatTokens(estimate.estimatedInputTokens),
              })
            }}
          </p>

          <div
            class="flex flex-col gap-1 rounded-lg bg-n-alpha-1 p-3 text-sm text-n-slate-11"
          >
            <p v-if="estimate.textAnalysis.avgCostUsd">
              {{
                t('AUDITORIA_AI_USAGE.BACKLOG_MODAL_TEXT_COST_WITH_HISTORY', {
                  avg: formatCost(estimate.textAnalysis.avgCostUsd),
                  n: estimate.textAnalysis.sampleSize,
                  estimated: formatCost(estimate.textAnalysis.estimatedCostUsd),
                })
              }}
            </p>
            <p v-else>
              {{ t('AUDITORIA_AI_USAGE.BACKLOG_MODAL_TEXT_COST_NO_HISTORY') }}
            </p>

            <template
              v-if="
                estimate.audioTranscription.sampleSize ||
                estimate.pendingAudioMessagesCount
              "
            >
              <p v-if="estimate.audioTranscription.avgCostUsd">
                {{
                  t(
                    'AUDITORIA_AI_USAGE.BACKLOG_MODAL_AUDIO_COST_WITH_HISTORY',
                    {
                      avg: formatCost(estimate.audioTranscription.avgCostUsd),
                      n: estimate.audioTranscription.sampleSize,
                      estimated: formatCost(
                        estimate.audioTranscription.estimatedCostUsd
                      ),
                    }
                  )
                }}
              </p>
              <p v-else>
                {{
                  t('AUDITORIA_AI_USAGE.BACKLOG_MODAL_AUDIO_COST_NO_HISTORY')
                }}
              </p>
            </template>

            <p class="font-medium text-n-slate-12">
              {{
                estimate.estimatedTotalCostUsd
                  ? t('AUDITORIA_AI_USAGE.BACKLOG_MODAL_TOTAL', {
                      total: formatCost(estimate.estimatedTotalCostUsd),
                    })
                  : t('AUDITORIA_AI_USAGE.BACKLOG_MODAL_TOTAL_UNKNOWN')
              }}
            </p>
          </div>

          <p class="text-xs text-n-slate-10">
            {{ t('AUDITORIA_AI_USAGE.BACKLOG_MODAL_DISCLAIMER') }}
          </p>
        </template>
      </template>
      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          type="button"
          :label="t('AUDITORIA_AI_USAGE.BACKLOG_MODAL_CANCEL')"
          @click="onClose"
        />
        <Button
          v-if="estimate?.candidateCount"
          type="button"
          :label="t('AUDITORIA_AI_USAGE.BACKLOG_MODAL_CONFIRM')"
          :is-loading="isRunning"
          :disabled="isLoadingEstimate"
          @click="onConfirm"
        />
      </div>
    </div>
  </div>
</template>
