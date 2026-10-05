<!-- Menu maestro de plantillas de WhatsApp: unifica lo que antes eran dos
paginas separadas (Ajustes > Plantillas, de solo lectura/sync sobre todas
las inboxes de WhatsApp; y Cartera > Plantillas, que creaba borradores y
los enviaba a aprobacion). Reusa los componentes genericos de la pagina de
Ajustes (TemplateCard, TemplatePreviewDrawer, templateUtils) en vez de
duplicarlos - la vieja Ajustes > Plantillas ahora es solo un redirect, ver
settings/templates/templates.routes.js. -->
<script setup>
import { computed, onMounted, onUnmounted, reactive, ref } from 'vue';
import { picoSearch } from '@chatwoot/pico-search';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import { INBOX_TYPES, TWILIO_CHANNEL_MEDIUM } from 'dashboard/helper/inbox';
import InboxesAPI from 'dashboard/api/inboxes';
import Spinner from 'shared/components/Spinner.vue';
import EmptyState from 'dashboard/components/widgets/EmptyState.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import plantillaAPI from 'dashboard/api/cartera/plantillasWhatsapp';
import CarteraHeader from '../cartera-shared/CarteraHeader.vue';
import TableCard from '../cartera-shared/TableCard.vue';
import TemplateCard from '../settings/templates/TemplateCard.vue';
import TemplatePreviewDrawer from '../settings/templates/TemplatePreviewDrawer.vue';
import {
  formatTemplateDate,
  formatTemplateLanguage,
  groupTemplates,
  templateTypeKey,
} from '../settings/templates/templateUtils';

const FUZZY_SEARCH_KEYS = [
  { name: 'name', weight: 4 },
  'category',
  'language',
  'status',
  'inboxNames',
  'searchableContent',
];

const { t } = useI18n();
const { isAdmin } = useAdmin();
const store = useStore();

/* ---------- Borradores (Cartera::PlantillaWhatsapp sin content_sid) ---------- */

const categoriaOptions = computed(() => [
  { value: 'utility', label: t('CARTERA.PLANTILLAS.CATEGORIAS.UTILITY') },
  { value: 'marketing', label: t('CARTERA.PLANTILLAS.CATEGORIAS.MARKETING') },
  {
    value: 'authentication',
    label: t('CARTERA.PLANTILLAS.CATEGORIAS.AUTHENTICATION'),
  },
]);

/* ---------- Plantillas sincronizadas (todas las inboxes de WhatsApp) ---------- */

const inboxes = useMapGetter('inboxes/getInboxes');
const templates = ref([]);
const searchQuery = ref('');
const selectedInboxId = ref('all');
const selectedLanguage = ref('all');
const selectedType = ref('all');
const selectedTemplate = ref(null);
const openFilterMenu = ref(null);
const previewPanelRef = ref(null);
const templateRecordsByInboxId = new Map();
const lastSyncAttemptsByInboxId = ref({});
const isSyncing = ref(false);
const {
  run: runTemplateRequest,
  abort: abortTemplateRequest,
  isPending: isLoadingTemplates,
} = useAbortableRequest();

const hasTemplates = computed(() => templates.value.length > 0);

const lastSyncAttemptAt = computed(() => {
  const timestamps = Object.values(lastSyncAttemptsByInboxId.value)
    .filter(Boolean)
    .map(value => new Date(value).getTime())
    .filter(Number.isFinite);

  return timestamps.length ? new Date(Math.max(...timestamps)) : null;
});

const typeLabels = computed(() => ({
  TEXT: t('WHATSAPP_TEMPLATE_MGMT.TYPES.TEXT'),
  IMAGE: t('WHATSAPP_TEMPLATE_MGMT.TYPES.IMAGE'),
  VIDEO: t('WHATSAPP_TEMPLATE_MGMT.TYPES.VIDEO'),
  DOCUMENT: t('WHATSAPP_TEMPLATE_MGMT.TYPES.DOCUMENT'),
  MEDIA: t('WHATSAPP_TEMPLATE_MGMT.TYPES.MEDIA'),
  QUICK_REPLY: t('WHATSAPP_TEMPLATE_MGMT.TYPES.QUICK_REPLY'),
  CALL_TO_ACTION: t('WHATSAPP_TEMPLATE_MGMT.TYPES.CALL_TO_ACTION'),
  CATALOG: t('WHATSAPP_TEMPLATE_MGMT.TYPES.CATALOG'),
  COPY_CODE: t('WHATSAPP_TEMPLATE_MGMT.TYPES.COPY_CODE'),
}));

const whatsappInboxes = computed(() =>
  inboxes.value.filter(
    inbox =>
      inbox.channel_type === INBOX_TYPES.WHATSAPP ||
      (inbox.channel_type === INBOX_TYPES.TWILIO &&
        inbox.medium === TWILIO_CHANNEL_MEDIUM.WHATSAPP)
  )
);

const inboxOptions = computed(() => [
  { value: 'all', label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_INBOXES') },
  ...whatsappInboxes.value.map(inbox => ({
    value: String(inbox.id),
    label: inbox.name,
  })),
]);

const languageOptions = computed(() => [
  { value: 'all', label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_LANGUAGES') },
  ...[...new Set(templates.value.map(template => template.language))]
    .filter(Boolean)
    .sort()
    .map(language => ({
      value: language,
      label: formatTemplateLanguage(language),
    })),
]);

const typeOptions = computed(() => [
  { value: 'all', label: t('WHATSAPP_TEMPLATE_MGMT.FILTERS.ALL_TYPES') },
  ...[...new Set(templates.value.map(templateTypeKey))]
    .map(type => ({ value: type, label: typeLabels.value[type] }))
    .sort((first, second) => first.label.localeCompare(second.label)),
]);

const filterMenus = computed(() =>
  [
    {
      key: 'inbox',
      icon: 'i-lucide-inbox',
      options: inboxOptions.value,
      active: selectedInboxId.value,
    },
    {
      key: 'language',
      icon: 'i-lucide-languages',
      options: languageOptions.value,
      active: selectedLanguage.value,
    },
    {
      key: 'type',
      icon: 'i-lucide-layout-template',
      options: typeOptions.value,
      active: selectedType.value,
    },
  ].map(menu => {
    const items = menu.options.map(option => ({
      ...option,
      action: menu.key,
      isSelected: option.value === menu.active,
    }));
    return {
      ...menu,
      items,
      selected: items.find(item => item.isSelected) || items[0],
    };
  })
);

const closeFilterMenu = () => {
  openFilterMenu.value = null;
};
const toggleFilterMenu = key => {
  openFilterMenu.value = openFilterMenu.value === key ? null : key;
};
const openPreview = template => {
  selectedTemplate.value = template;
  previewPanelRef.value?.open();
};
const handleFilterAction = ({ action, value }) => {
  closeFilterMenu();
  if (action === 'inbox') selectedInboxId.value = value;
  else if (action === 'language') selectedLanguage.value = value;
  else selectedType.value = value;
};

const filteredTemplates = computed(() => {
  let records = templates.value;

  if (selectedInboxId.value !== 'all') {
    records = records.filter(template =>
      template.inboxes.some(inbox => String(inbox.id) === selectedInboxId.value)
    );
  }
  if (selectedLanguage.value !== 'all') {
    records = records.filter(
      template => template.language === selectedLanguage.value
    );
  }
  if (selectedType.value !== 'all') {
    records = records.filter(
      template => templateTypeKey(template) === selectedType.value
    );
  }

  const query = searchQuery.value.trim();
  if (!query) return records;

  const normalizedQuery = query.toLowerCase();
  const contentMatches = records.filter(template =>
    [template.name, template.searchableContent].some(value =>
      value?.toLowerCase().includes(normalizedQuery)
    )
  );
  if (contentMatches.length) return contentMatches;

  return picoSearch(records, query, FUZZY_SEARCH_KEYS);
});

const showSearch = computed(() =>
  Boolean(filteredTemplates.value.length || searchQuery.value)
);

const fetchTemplates = async () => {
  try {
    await runTemplateRequest(async signal => {
      const didFetchInboxes = await store.dispatch('inboxes/get');
      if (!didFetchInboxes) throw new Error();
      if (signal.aborted) return;

      const inboxesToFetch = [...whatsappInboxes.value];
      const responses = await Promise.allSettled(
        inboxesToFetch.map(async inbox => {
          const { data } = await InboxesAPI.getMessageTemplates(
            inbox.id,
            {},
            { signal }
          );
          if (!Array.isArray(data.payload)) throw new TypeError();

          return {
            inboxId: inbox.id,
            lastSyncAttemptAt: data.meta?.last_sync_attempt_at,
            records: data.payload.map(template => ({
              template,
              inbox,
              lastUpdatedAt: data.meta?.last_sync_attempt_at,
            })),
          };
        })
      );
      if (signal.aborted) return;

      const successfulResponses = responses.filter(
        response => response.status === 'fulfilled'
      );
      const activeInboxIds = new Set(inboxesToFetch.map(inbox => inbox.id));
      const nextLastSyncAttempts = { ...lastSyncAttemptsByInboxId.value };

      templateRecordsByInboxId.forEach((_, inboxId) => {
        if (!activeInboxIds.has(inboxId)) {
          templateRecordsByInboxId.delete(inboxId);
          delete nextLastSyncAttempts[inboxId];
        }
      });
      successfulResponses.forEach(({ value }) => {
        templateRecordsByInboxId.set(value.inboxId, value.records);
        nextLastSyncAttempts[value.inboxId] = value.lastSyncAttemptAt;
      });
      lastSyncAttemptsByInboxId.value = nextLastSyncAttempts;
      templates.value = groupTemplates(
        [...templateRecordsByInboxId.values()].flat()
      );

      if (
        !inboxOptions.value.some(({ value }) => value === selectedInboxId.value)
      )
        selectedInboxId.value = 'all';
      if (
        !languageOptions.value.some(
          ({ value }) => value === selectedLanguage.value
        )
      )
        selectedLanguage.value = 'all';
      if (!typeOptions.value.some(({ value }) => value === selectedType.value))
        selectedType.value = 'all';

      if (responses.some(response => response.status === 'rejected')) {
        const errorMessage = successfulResponses.length
          ? t('WHATSAPP_TEMPLATE_MGMT.PARTIAL_FETCH_ERROR')
          : t('WHATSAPP_TEMPLATE_MGMT.FETCH_ERROR');
        useAlert(errorMessage);
      }
    });
  } catch {
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.FETCH_ERROR'));
  }
};

const syncTemplates = async () => {
  if (isSyncing.value) return;
  isSyncing.value = true;

  const responses = await Promise.allSettled(
    whatsappInboxes.value.map(inbox =>
      store.dispatch('inboxes/syncTemplates', inbox.id)
    )
  );
  const failedCount = responses.filter(
    response => response.status === 'rejected'
  ).length;

  if (!failedCount) useAlert(t('WHATSAPP_TEMPLATE_MGMT.SYNC_SUCCESS'));
  else if (failedCount < responses.length)
    useAlert(t('WHATSAPP_TEMPLATE_MGMT.PARTIAL_SYNC_ERROR'));
  else useAlert(t('WHATSAPP_TEMPLATE_MGMT.SYNC_ERROR'));

  isSyncing.value = false;
  await fetchTemplates();
};

/* ---------- Borradores (Cartera::PlantillaWhatsapp sin content_sid) ---------- */

const borradores = ref([]);
const isFetchingBorradores = ref(false);
const soloBorradores = computed(() =>
  borradores.value.filter(plantilla => !plantilla.content_sid)
);

const fetchBorradores = async () => {
  isFetchingBorradores.value = true;
  try {
    const { data } = await plantillaAPI.get();
    borradores.value = data;
  } finally {
    isFetchingBorradores.value = false;
  }
};

const solicitandoId = ref(null);
const solicitarAprobacion = async plantilla => {
  solicitandoId.value = plantilla.id;
  try {
    await plantillaAPI.solicitarAprobacion(plantilla.id);
    useAlert(t('CARTERA.PLANTILLAS.SOLICITUD_EXITOSA'));
    await Promise.all([fetchBorradores(), fetchTemplates()]);
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CARTERA.PLANTILLAS.SOLICITUD_ERROR')
    );
  } finally {
    solicitandoId.value = null;
  }
};

const dialogRef = ref(null);
const isSaving = ref(false);
const form = reactive({ nombre: '', categoria: 'utility', cuerpo: '' });

const abrirDialogo = () => {
  form.nombre = '';
  form.categoria = 'utility';
  form.cuerpo = '';
  dialogRef.value?.open();
};

const crearPlantilla = async () => {
  isSaving.value = true;
  try {
    await plantillaAPI.create({ ...form });
    useAlert(t('CARTERA.PLANTILLAS.CREADA_EXITOSA'));
    dialogRef.value?.close();
    await fetchBorradores();
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('CARTERA.PLANTILLAS.CREADA_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

onMounted(() => {
  fetchBorradores();
  fetchTemplates();
});
onUnmounted(abortTemplateRequest);
</script>

<template>
  <div>
    <CarteraHeader :header-title="t('CARTERA.PLANTILLAS.TITLE')">
      <div class="flex items-center gap-2">
        <Button
          :label="t('WHATSAPP_TEMPLATE_MGMT.SYNC_TEMPLATES')"
          icon="i-lucide-refresh-cw"
          color="slate"
          size="sm"
          :is-loading="isSyncing"
          :disabled="!whatsappInboxes.length || isSyncing"
          @click="syncTemplates"
        />
        <Button
          v-if="isAdmin"
          icon="i-lucide-plus"
          size="sm"
          :label="t('CARTERA.PLANTILLAS.NUEVA')"
          @click="abrirDialogo"
        />
      </div>
    </CarteraHeader>

    <!-- Borradores: Cartera::PlantillaWhatsapp que aun no se enviaron a Twilio -->
    <div v-if="soloBorradores.length" class="mb-6">
      <h3 class="text-heading-3 text-n-slate-12 mb-2">
        {{ t('CARTERA.PLANTILLAS.BORRADORES_TITLE') }}
      </h3>
      <TableCard>
        <div class="divide-y divide-n-weak">
          <div
            v-for="plantilla in soloBorradores"
            :key="plantilla.id"
            class="flex items-center justify-between gap-4 py-4 px-5"
          >
            <div class="flex flex-col min-w-0 gap-1">
              <span class="truncate text-heading-3 text-n-slate-12">
                {{ plantilla.nombre }}
              </span>
              <span class="text-body-main text-n-slate-11 line-clamp-1">
                {{ plantilla.cuerpo }}
              </span>
            </div>
            <Button
              v-if="isAdmin"
              size="sm"
              slate
              faded
              class="shrink-0"
              :label="t('CARTERA.PLANTILLAS.SOLICITAR_APROBACION')"
              :is-loading="solicitandoId === plantilla.id"
              @click="solicitarAprobacion(plantilla)"
            />
          </div>
        </div>
      </TableCard>
    </div>
    <div
      v-else-if="isFetchingBorradores"
      class="flex items-center justify-center py-4"
    >
      <Spinner />
    </div>

    <!-- Plantillas sincronizadas desde Twilio/WhatsApp (todas las inboxes) -->
    <Input
      v-if="showSearch"
      v-model="searchQuery"
      class="mb-3 max-w-sm"
      :placeholder="t('WHATSAPP_TEMPLATE_MGMT.SEARCH_PLACEHOLDER')"
    />
    <div
      v-if="hasTemplates"
      v-on-click-outside="closeFilterMenu"
      class="flex items-center gap-2 mb-3"
    >
      <div v-for="menu in filterMenus" :key="menu.key" class="relative">
        <Button
          :icon="menu.icon"
          color="slate"
          size="sm"
          :class="{ 'bg-n-slate-9/10': openFilterMenu === menu.key }"
          @click="toggleFilterMenu(menu.key)"
        >
          <span class="min-w-0 truncate">{{ menu.selected.label }}</span>
          <Icon icon="i-lucide-chevron-down" class="shrink-0 size-4" />
        </Button>
        <DropdownMenu
          v-if="openFilterMenu === menu.key"
          :menu-items="menu.items"
          class="mt-2 min-w-52 top-full ltr:left-0 rtl:right-0"
          @action="handleFilterAction"
        />
      </div>
      <span v-if="lastSyncAttemptAt" class="text-xs text-n-slate-10 ms-auto">
        {{
          t('WHATSAPP_TEMPLATE_MGMT.LAST_SYNC_ATTEMPT', {
            date: formatTemplateDate(lastSyncAttemptAt),
          })
        }}
      </span>
    </div>

    <TableCard>
      <div
        v-if="isLoadingTemplates && !templates.length"
        class="flex items-center justify-center py-16"
      >
        <Spinner />
      </div>
      <EmptyState
        v-else-if="!isLoadingTemplates && !filteredTemplates.length"
        :title="t('WHATSAPP_TEMPLATE_MGMT.EMPTY')"
      />
      <div v-else class="divide-y divide-n-weak px-5">
        <TemplateCard
          v-for="template in filteredTemplates"
          :key="template.key"
          :template="template"
          @preview="openPreview(template)"
        />
      </div>
    </TableCard>

    <TemplatePreviewDrawer ref="previewPanelRef" :template="selectedTemplate" />

    <Dialog
      ref="dialogRef"
      :title="t('CARTERA.PLANTILLAS.NUEVA')"
      :description="t('CARTERA.PLANTILLAS.NUEVA_DESCRIPCION')"
      :confirm-button-label="t('CARTERA.PLANTILLAS.GUARDAR')"
      :is-loading="isSaving"
      :disable-confirm-button="!form.nombre || !form.cuerpo"
      @confirm="crearPlantilla"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="form.nombre"
          :label="t('CARTERA.PLANTILLAS.FORM.NOMBRE')"
          :placeholder="t('CARTERA.PLANTILLAS.FORM.NOMBRE_PLACEHOLDER')"
        />
        <div class="flex flex-col gap-1">
          <label class="text-sm text-n-slate-12">
            {{ t('CARTERA.PLANTILLAS.FORM.CATEGORIA') }}
          </label>
          <Select v-model="form.categoria" :options="categoriaOptions" />
        </div>
        <TextArea
          v-model="form.cuerpo"
          :label="t('CARTERA.PLANTILLAS.FORM.CUERPO')"
          :placeholder="t('CARTERA.PLANTILLAS.FORM.CUERPO_PLACEHOLDER')"
          :max-length="1024"
          show-character-count
          auto-height
        />
        <p class="text-n-slate-11 text-sm mb-0">
          {{ t('CARTERA.PLANTILLAS.FORM.CUERPO_AYUDA') }}
        </p>
      </div>
    </Dialog>
  </div>
</template>
