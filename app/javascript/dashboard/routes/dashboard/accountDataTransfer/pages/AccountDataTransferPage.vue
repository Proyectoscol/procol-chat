<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const { t } = useI18n();
const store = useStore();

const allInboxes = useMapGetter('inboxes/getInboxes');
const exports = useMapGetter('calendarioAccountDataExports/getExports');
const imports = useMapGetter('calendarioAccountDataImports/getImports');

const inboxOptions = computed(() => [
  { value: '', label: t('ACCOUNT_DATA_TRANSFER.IMPORT.INBOX_PLACEHOLDER') },
  ...allInboxes.value.map(inbox => ({ value: inbox.id, label: inbox.name })),
]);

const isExporting = ref(false);
const isImporting = ref(false);
const importInboxId = ref('');
const importFile = ref(null);
let pollTimer = null;

const statusColorClass = status => {
  const map = {
    completed: 'text-n-teal-11',
    failed: 'text-n-ruby-11',
    processing: 'text-n-blue-11',
  };
  return map[status] || 'text-n-slate-11';
};

const statusLabel = status =>
  t(`ACCOUNT_DATA_TRANSFER.STATUS.${status.toUpperCase()}`);

const exportTableHeaders = computed(() => [
  t('ACCOUNT_DATA_TRANSFER.EXPORT.TABLE.DATE'),
  t('ACCOUNT_DATA_TRANSFER.EXPORT.TABLE.STATUS'),
  t('ACCOUNT_DATA_TRANSFER.EXPORT.TABLE.COUNTS'),
  t('ACCOUNT_DATA_TRANSFER.EXPORT.TABLE.DOWNLOAD'),
]);

const importTableHeaders = computed(() => [
  t('ACCOUNT_DATA_TRANSFER.IMPORT.TABLE.DATE'),
  t('ACCOUNT_DATA_TRANSFER.IMPORT.TABLE.INBOX'),
  t('ACCOUNT_DATA_TRANSFER.IMPORT.TABLE.STATUS'),
  t('ACCOUNT_DATA_TRANSFER.IMPORT.TABLE.RESULT'),
]);

const manifestSummary = manifest => {
  const counts = manifest?.counts;
  if (!counts) return '';
  return [
    'contacts',
    'conversations',
    'messages',
    'attachments',
    'appointments',
  ]
    .map(key => `${key}: ${counts[key] ?? 0}`)
    .join(', ');
};

const importResultSummary = importRecord => {
  if (importRecord.status === 'failed') return importRecord.error_message;
  if (importRecord.status !== 'completed') return '';
  const stats = importRecord.stats || {};
  return Object.entries(stats)
    .map(([key, value]) => `${key}: ${value.created}+${value.reused}`)
    .join(', ');
};

const runExport = async () => {
  isExporting.value = true;
  try {
    await store.dispatch('calendarioAccountDataExports/create');
    useAlert(t('ACCOUNT_DATA_TRANSFER.EXPORT.STARTED'));
  } catch (error) {
    useAlert(t('ACCOUNT_DATA_TRANSFER.EXPORT.ERROR'));
  } finally {
    isExporting.value = false;
  }
};

const onImportFileSelected = event => {
  importFile.value = event.target.files?.[0] || null;
};

const canRunImport = computed(
  () => !isImporting.value && importInboxId.value && importFile.value
);

const runImport = async () => {
  isImporting.value = true;
  try {
    await store.dispatch('calendarioAccountDataImports/create', {
      importFile: importFile.value,
      inboxId: importInboxId.value,
    });
    importFile.value = null;
    useAlert(t('ACCOUNT_DATA_TRANSFER.IMPORT.STARTED'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('ACCOUNT_DATA_TRANSFER.IMPORT.ERROR')
    );
  } finally {
    isImporting.value = false;
  }
};

const hasInFlightExports = computed(() =>
  exports.value.some(item => ['pending', 'processing'].includes(item.status))
);
const hasInFlightImports = computed(() =>
  imports.value.some(item => ['pending', 'processing'].includes(item.status))
);

const fetchAll = () =>
  Promise.all([
    store.dispatch('calendarioAccountDataExports/get'),
    store.dispatch('calendarioAccountDataImports/get'),
  ]);

onMounted(async () => {
  try {
    await Promise.all([store.dispatch('inboxes/get'), fetchAll()]);
  } catch (error) {
    useAlert(t('ACCOUNT_DATA_TRANSFER.FETCH_ERROR'));
  }
  pollTimer = setInterval(() => {
    if (hasInFlightExports.value || hasInFlightImports.value) fetchAll();
  }, 5000);
});

onBeforeUnmount(() => {
  if (pollTimer) clearInterval(pollTimer);
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-y-auto p-6 gap-8">
    <div class="flex flex-col gap-1">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('ACCOUNT_DATA_TRANSFER.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11">
        {{ t('ACCOUNT_DATA_TRANSFER.DESCRIPTION') }}
      </p>
    </div>

    <div class="flex flex-col gap-3">
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('ACCOUNT_DATA_TRANSFER.EXPORT.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('ACCOUNT_DATA_TRANSFER.EXPORT.DESCRIPTION') }}
      </p>
      <Button
        class="w-fit"
        :label="t('ACCOUNT_DATA_TRANSFER.EXPORT.BUTTON')"
        :is-loading="isExporting"
        @click="runExport"
      />
      <BaseTable
        v-if="exports.length"
        :headers="exportTableHeaders"
        :items="exports"
      >
        <template #row="{ items }">
          <BaseTableRow v-for="item in items" :key="item.id" :item="item">
            <template #default>
              <BaseTableCell>{{ item.created_at }}</BaseTableCell>
              <BaseTableCell>
                <span :class="statusColorClass(item.status)">
                  {{ statusLabel(item.status) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-xs text-n-slate-11">{{
                  manifestSummary(item.manifest)
                }}</span>
              </BaseTableCell>
              <BaseTableCell>
                <a
                  v-if="item.download_url"
                  :href="item.download_url"
                  class="text-n-blue-11 text-sm underline"
                >
                  {{ t('ACCOUNT_DATA_TRANSFER.EXPORT.TABLE.DOWNLOAD_LINK') }}
                </a>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>

    <div class="flex flex-col gap-3">
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('ACCOUNT_DATA_TRANSFER.IMPORT.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11">
        {{ t('ACCOUNT_DATA_TRANSFER.IMPORT.DESCRIPTION') }}
      </p>

      <div
        class="flex flex-col gap-4 max-w-2xl border border-n-weak rounded-xl p-4"
      >
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('ACCOUNT_DATA_TRANSFER.IMPORT.INBOX_LABEL') }}
          </label>
          <Select v-model="importInboxId" :options="inboxOptions" />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('ACCOUNT_DATA_TRANSFER.IMPORT.FILE_LABEL') }}
          </label>
          <input
            type="file"
            accept=".zip"
            class="text-sm text-n-slate-11"
            @change="onImportFileSelected"
          />
        </div>
        <Button
          class="w-fit"
          :label="t('ACCOUNT_DATA_TRANSFER.IMPORT.BUTTON')"
          :is-loading="isImporting"
          :disabled="!canRunImport"
          @click="runImport"
        />
      </div>

      <BaseTable
        v-if="imports.length"
        :headers="importTableHeaders"
        :items="imports"
      >
        <template #row="{ items }">
          <BaseTableRow v-for="item in items" :key="item.id" :item="item">
            <template #default>
              <BaseTableCell>{{ item.created_at }}</BaseTableCell>
              <BaseTableCell>{{ item.inbox_name }}</BaseTableCell>
              <BaseTableCell>
                <span :class="statusColorClass(item.status)">
                  {{ statusLabel(item.status) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-xs text-n-slate-11">{{
                  importResultSummary(item)
                }}</span>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
  </div>
</template>
