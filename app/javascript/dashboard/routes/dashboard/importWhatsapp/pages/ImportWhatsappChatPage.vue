<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const { t } = useI18n();
const store = useStore();

const allInboxes = useMapGetter('inboxes/getInboxes');
const batches = useMapGetter('importWhatsappChatBatches/getBatches');

// Mientras no haya un inbox de WhatsApp real conectado, mostrar todos los
// inboxes evita que esta pantalla quede inutilizable en desarrollo/pruebas
// -- en produccion, con el inbox real ya creado, el filtro aplica solo.
const inboxOptions = computed(() => {
  const whatsappInboxes = allInboxes.value.filter(
    inbox => inbox.channel_type === 'Channel::Whatsapp'
  );
  const source = whatsappInboxes.length ? whatsappInboxes : allInboxes.value;
  return [
    { value: '', label: t('IMPORT_WHATSAPP.FORM.INBOX_PLACEHOLDER') },
    ...source.map(inbox => ({ value: inbox.id, label: inbox.name })),
  ];
});

const inboxId = ref('');
const usSenderName = ref('');
const fileInput = ref(null);
const rows = ref([]);
const isUploading = ref(false);
let pollTimer = null;

// Intenta precargar el numero si el nombre del archivo ya lo trae (caso
// comun cuando el contacto no esta guardado en el telefono que exporto) --
// nunca bloquea, es solo una ayuda, el campo sigue siendo editable.
const guessPhoneNumber = filename => {
  const digits = filename.replace(/\D/g, '');
  return digits.length >= 7 ? digits : '';
};

const onFilesSelected = event => {
  const files = Array.from(event.target.files || []);
  rows.value = files.map(file => ({
    file,
    filename: file.name,
    phoneNumber: guessPhoneNumber(file.name),
    status: 'pending',
    error: '',
  }));
};

const canUploadAll = computed(
  () =>
    !isUploading.value &&
    inboxId.value &&
    usSenderName.value.trim() &&
    rows.value.some(row => row.status === 'pending' && row.phoneNumber.trim())
);

const uploadRow = async row => {
  row.status = 'uploading';
  try {
    await store.dispatch('importWhatsappChatBatches/create', {
      zipFile: row.file,
      inboxId: inboxId.value,
      usSenderName: usSenderName.value.trim(),
      phoneNumber: row.phoneNumber.trim(),
      originalFilename: row.filename,
    });
    row.status = 'uploaded';
  } catch (error) {
    row.status = 'error';
    row.error =
      error?.response?.data?.error || t('IMPORT_WHATSAPP.FORM.UPLOAD_ERROR');
  }
};

// Secuencial a proposito: con cientos de zips pesados (fotos/videos), mil
// subidas en paralelo saturarian la conexion del navegador sin ganar nada
// -- el procesamiento real de todos modos ocurre en el backend en paralelo
// via Sidekiq, esto solo limita cuantas subidas estan en vuelo a la vez.
const uploadAll = async () => {
  isUploading.value = true;
  try {
    const pending = rows.value.filter(
      row => row.status === 'pending' && row.phoneNumber.trim()
    );
    await pending.reduce(
      (promise, row) => promise.then(() => uploadRow(row)),
      Promise.resolve()
    );
    useAlert(t('IMPORT_WHATSAPP.FORM.UPLOAD_ALL_DONE'));
  } finally {
    isUploading.value = false;
  }
};

const statusLabel = status =>
  t(`IMPORT_WHATSAPP.BATCHES.STATUS.${status.toUpperCase()}`);

const statusColorClass = status => {
  const map = {
    completed: 'text-n-teal-11',
    failed: 'text-n-ruby-11',
    needs_review: 'text-n-amber-11',
    processing: 'text-n-blue-11',
  };
  return map[status] || 'text-n-slate-11';
};

const tableHeaders = computed(() => [
  t('IMPORT_WHATSAPP.BATCHES.TABLE.FILE'),
  t('IMPORT_WHATSAPP.BATCHES.TABLE.PHONE'),
  t('IMPORT_WHATSAPP.BATCHES.TABLE.CONTACT'),
  t('IMPORT_WHATSAPP.BATCHES.TABLE.STATUS'),
  t('IMPORT_WHATSAPP.BATCHES.TABLE.RESULT'),
]);

const resultSummary = batch => {
  if (batch.status === 'needs_review' || batch.status === 'failed') {
    return batch.error_message;
  }
  if (batch.status === 'completed') {
    return t('IMPORT_WHATSAPP.BATCHES.TABLE.RESULT_SUMMARY', {
      imported: batch.stats?.imported ?? 0,
      skipped: batch.stats?.skipped_duplicate ?? 0,
      attachments: batch.stats?.attachments_uploaded ?? 0,
    });
  }
  return '';
};

const hasInFlightBatches = computed(() =>
  batches.value.some(batch => ['pending', 'processing'].includes(batch.status))
);

const fetchBatches = () => store.dispatch('importWhatsappChatBatches/get');

onMounted(async () => {
  try {
    await Promise.all([store.dispatch('inboxes/get'), fetchBatches()]);
  } catch (error) {
    useAlert(t('IMPORT_WHATSAPP.FETCH_ERROR'));
  }
  // Mientras haya batches en cola/procesando, refresca solo para que el
  // estado se vea avanzar sin que la persona tenga que recargar la pagina.
  pollTimer = setInterval(() => {
    if (hasInFlightBatches.value) fetchBatches();
  }, 5000);
});

onBeforeUnmount(() => {
  if (pollTimer) clearInterval(pollTimer);
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-y-auto p-6 gap-6">
    <div class="flex flex-col gap-1">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ t('IMPORT_WHATSAPP.TITLE') }}
      </h1>
      <p class="text-sm text-n-slate-11">
        {{ t('IMPORT_WHATSAPP.DESCRIPTION') }}
      </p>
    </div>

    <div
      class="flex flex-col gap-4 max-w-2xl border border-n-weak rounded-xl p-4"
    >
      <div class="grid grid-cols-2 gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('IMPORT_WHATSAPP.FORM.INBOX_LABEL') }}
          </label>
          <Select v-model="inboxId" :options="inboxOptions" />
        </div>
        <Input
          v-model="usSenderName"
          :label="t('IMPORT_WHATSAPP.FORM.US_SENDER_LABEL')"
          :placeholder="t('IMPORT_WHATSAPP.FORM.US_SENDER_PLACEHOLDER')"
        />
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('IMPORT_WHATSAPP.FORM.FILES_LABEL') }}
        </label>
        <input
          ref="fileInput"
          type="file"
          multiple
          accept=".zip"
          class="text-sm text-n-slate-11"
          @change="onFilesSelected"
        />
      </div>

      <div
        v-if="rows.length"
        class="flex flex-col gap-2 max-h-72 overflow-y-auto border border-n-weak rounded-lg p-2"
      >
        <div
          v-for="row in rows"
          :key="row.filename"
          class="flex items-center gap-2"
        >
          <span class="flex-1 text-sm text-n-slate-12 truncate">{{
            row.filename
          }}</span>
          <Input
            v-model="row.phoneNumber"
            class="w-40"
            :placeholder="t('IMPORT_WHATSAPP.FORM.PHONE_PLACEHOLDER')"
            :disabled="row.status !== 'pending'"
          />
          <span
            class="text-xs w-20 shrink-0"
            :class="statusColorClass(row.status)"
          >
            {{ t(`IMPORT_WHATSAPP.ROW_STATUS.${row.status.toUpperCase()}`) }}
          </span>
        </div>
      </div>

      <Button
        :label="t('IMPORT_WHATSAPP.FORM.UPLOAD_ALL')"
        :is-loading="isUploading"
        :disabled="!canUploadAll"
        @click="uploadAll"
      />
    </div>

    <div class="flex flex-col gap-2">
      <h2 class="text-base font-medium text-n-slate-12">
        {{ t('IMPORT_WHATSAPP.BATCHES.TITLE') }}
      </h2>
      <div v-if="!batches.length" class="flex items-center justify-center py-8">
        <Spinner />
      </div>
      <BaseTable v-else :headers="tableHeaders" :items="batches">
        <template #row="{ items }">
          <BaseTableRow v-for="batch in items" :key="batch.id" :item="batch">
            <template #default>
              <BaseTableCell>{{ batch.original_filename }}</BaseTableCell>
              <BaseTableCell>{{ batch.phone_number }}</BaseTableCell>
              <BaseTableCell>{{ batch.contact_name || '—' }}</BaseTableCell>
              <BaseTableCell>
                <span :class="statusColorClass(batch.status)">
                  {{ statusLabel(batch.status) }}
                </span>
              </BaseTableCell>
              <BaseTableCell>
                <span class="text-xs text-n-slate-11">{{
                  resultSummary(batch)
                }}</span>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
  </div>
</template>
