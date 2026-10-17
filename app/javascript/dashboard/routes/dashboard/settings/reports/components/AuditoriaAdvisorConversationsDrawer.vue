<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ReportDrilldownCard from './ReportDrilldownCard.vue';
import { useReportDrilldown } from '../composables/useReportDrilldown';
import SummaryReportsAPI from 'dashboard/api/summaryReports';

const props = defineProps({
  open: { type: Boolean, default: false },
  advisorName: { type: String, default: '' },
  userId: { type: [String, Number], default: null },
  since: { type: Number, default: null },
  until: { type: Number, default: null },
  inboxId: { type: [String, Number], default: '' },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const panelRef = ref(null);

const fetcher = ({ userId, since, until, inboxId, page, signal }) =>
  SummaryReportsAPI.getAuditoriaAdvisorConversations({
    since,
    until,
    inboxId,
    userId,
    page,
    signal,
  });

const {
  records,
  meta,
  isFetching,
  isFetchingMore,
  hasError,
  hasRecords,
  hasMore,
  open: openDrilldown,
  close,
  loadMore,
} = useReportDrilldown(fetcher);

const recordKey = record => record.conversation?.id;

const fetchConversations = () => {
  openDrilldown({
    userId: props.userId,
    since: props.since,
    until: props.until,
    inboxId: props.inboxId,
  });
};

watch(
  () => props.open,
  isDrawerOpen => {
    if (!isDrawerOpen) {
      panelRef.value?.close();
      close();
      return;
    }

    panelRef.value?.open();
    fetchConversations();
  }
);
</script>

<template>
  <SidePanel
    ref="panelRef"
    :title="advisorName"
    :description="
      t('AUDITORIA_ADVISOR_REPORTS.CONVERSATIONS_DRAWER.DESCRIPTION')
    "
    width="xl"
    @close="emit('close')"
  >
    <div v-if="isFetching" class="flex h-40 items-center justify-center">
      <Spinner />
    </div>

    <div
      v-else-if="hasError"
      class="flex h-40 items-center justify-center text-sm text-n-ruby-11"
    >
      {{ t('AUDITORIA_ADVISOR_REPORTS.CONVERSATIONS_DRAWER.ERROR') }}
    </div>

    <div
      v-else-if="!hasRecords"
      class="flex h-40 items-center justify-center text-sm text-n-slate-10"
    >
      {{ t('AUDITORIA_ADVISOR_REPORTS.CONVERSATIONS_DRAWER.EMPTY') }}
    </div>

    <div v-else class="flex flex-col gap-2">
      <p class="text-sm text-n-slate-11 mb-1">
        {{
          t('AUDITORIA_ADVISOR_REPORTS.CONVERSATIONS_DRAWER.RESULT_COUNT', {
            count: meta.total_count,
          })
        }}
      </p>
      <ReportDrilldownCard
        v-for="record in records"
        :key="recordKey(record)"
        :record="record"
      />

      <Button
        v-if="hasMore"
        faded
        slate
        size="sm"
        class="mx-auto mt-2"
        :label="t('REPORT.DRILLDOWN.LOAD_MORE')"
        :is-loading="isFetchingMore"
        @click="loadMore"
      />
    </div>
  </SidePanel>
</template>
