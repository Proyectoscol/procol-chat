<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

const props = defineProps({
  trigger: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const whatsappInboxes = useMapGetter('inboxes/getWhatsAppInboxes');
const getFilteredWhatsAppTemplates = useMapGetter(
  'inboxes/getFilteredWhatsAppTemplates'
);
const services = useMapGetter('calendarioServices/getServices');

const isEditMode = computed(() => !!props.trigger);

const TARGET_STATUSES = [
  'pending',
  'confirmed',
  'attended',
  'no_show',
  'cancelled',
];

const triggerKind = ref('on_create');
const targetStatus = ref('');
const offsetMinutes = ref('');
const serviceId = ref('');
const inboxId = ref('');
const templateId = ref('');
const active = ref(true);
const isSaving = ref(false);
const templateParserRef = ref(null);

const setFormValues = () => {
  triggerKind.value = props.trigger?.trigger_kind || 'on_create';
  targetStatus.value = props.trigger?.target_status || '';
  offsetMinutes.value = props.trigger?.offset_minutes ?? '';
  serviceId.value = props.trigger?.service_id ?? '';
  inboxId.value = props.trigger?.inbox_id ?? '';
  active.value = props.trigger ? props.trigger.active : true;
  // La plantilla elegida se resuelve de nuevo por nombre+idioma una vez
  // carguen los templates del inbox (ver watch de inboxId más abajo);
  // no se puede resolver aquí porque todavía no sabemos el id interno.
  templateId.value = '';
};
watch(() => props.trigger, setFormValues, { immediate: true });

onMounted(() => {
  store.dispatch('inboxes/get');
  store.dispatch('calendarioServices/get');
});

const kindOptions = computed(() => [
  {
    value: 'on_create',
    label: t('CALENDARIO.TRIGGERS.FORM.KIND_OPTIONS.ON_CREATE'),
  },
  {
    value: 'on_status_change',
    label: t('CALENDARIO.TRIGGERS.FORM.KIND_OPTIONS.ON_STATUS_CHANGE'),
  },
  {
    value: 'before_start',
    label: t('CALENDARIO.TRIGGERS.FORM.KIND_OPTIONS.BEFORE_START'),
  },
]);

const targetStatusOptions = computed(() => [
  {
    value: '',
    label: t('CALENDARIO.TRIGGERS.FORM.TARGET_STATUS_PLACEHOLDER'),
  },
  ...TARGET_STATUSES.map(status => ({
    value: status,
    label: t(`CALENDARIO.APPOINTMENTS.STATUS.${status.toUpperCase()}`),
  })),
]);

const serviceOptions = computed(() => [
  { value: '', label: t('CALENDARIO.TRIGGERS.FORM.SERVICE_PLACEHOLDER') },
  ...services.value.map(service => ({
    value: service.id,
    label: service.name,
  })),
]);

const inboxOptions = computed(() => [
  { value: '', label: t('CALENDARIO.TRIGGERS.FORM.INBOX_PLACEHOLDER') },
  ...whatsappInboxes.value.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  })),
]);

const approvedTemplates = computed(() => {
  if (!inboxId.value) return [];
  return getFilteredWhatsAppTemplates.value(inboxId.value);
});

const templateOptions = computed(() => [
  { value: '', label: t('CALENDARIO.TRIGGERS.FORM.TEMPLATE_PLACEHOLDER') },
  ...approvedTemplates.value.map(template => ({
    value: template.id,
    label: `${template.name} (${template.language || ''})`,
  })),
]);

const selectedTemplate = computed(() => {
  if (!templateId.value) return null;
  return approvedTemplates.value.find(
    template => String(template.id) === String(templateId.value)
  );
});

// Al cambiar de bandeja, la plantilla elegida ya no aplica (es por bandeja).
watch(inboxId, () => {
  templateId.value = '';
});

// Una vez cargan los templates del inbox en modo edicion, intenta re-elegir
// la plantilla que ya tenia guardada el trigger (name+language en
// template_params, buscado contra la lista de aprobadas de ese inbox).
watch(
  approvedTemplates,
  templates => {
    if (!isEditMode.value || templateId.value) return;
    const saved = props.trigger?.template_params;
    if (!saved?.name) return;
    const match = templates.find(
      template =>
        template.name === saved.name &&
        (!saved.language || template.language === saved.language)
    );
    if (match) templateId.value = match.id;
  },
  { immediate: true }
);

const isFormInvalid = computed(() => {
  if (!inboxId.value || !templateId.value) return true;
  if (triggerKind.value === 'on_status_change' && !targetStatus.value) {
    return true;
  }
  if (triggerKind.value === 'before_start' && !offsetMinutes.value) {
    return true;
  }
  return false;
});

const onClose = () => emit('close');

const submit = async () => {
  if (!selectedTemplate.value) return;
  templateParserRef.value?.v$?.$touch();
  if (templateParserRef.value?.v$?.$invalid) return;

  isSaving.value = true;
  const { name, category, language, namespace } = selectedTemplate.value;
  const payload = {
    trigger_kind: triggerKind.value,
    target_status:
      triggerKind.value === 'on_status_change' ? targetStatus.value : null,
    offset_minutes:
      triggerKind.value === 'before_start' ? Number(offsetMinutes.value) : null,
    service_id: serviceId.value || null,
    inbox_id: inboxId.value,
    active: active.value,
    template_params: {
      name,
      category,
      language,
      namespace,
      processed_params: templateParserRef.value?.processedParams || {},
    },
  };
  try {
    if (isEditMode.value) {
      await store.dispatch('calendarioAppointmentEventTriggers/update', {
        id: props.trigger.id,
        ...payload,
      });
      useAlert(t('CALENDARIO.TRIGGERS.FORM.EDIT_SUCCESS'));
    } else {
      await store.dispatch(
        'calendarioAppointmentEventTriggers/create',
        payload
      );
      useAlert(t('CALENDARIO.TRIGGERS.FORM.CREATE_SUCCESS'));
    }
    onClose();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CALENDARIO.TRIGGERS.FORM.ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="
        isEditMode
          ? t('CALENDARIO.TRIGGERS.FORM.EDIT_TITLE')
          : t('CALENDARIO.TRIGGERS.FORM.CREATE_TITLE')
      "
    />
    <form
      class="flex flex-col gap-4 px-4 pb-4 w-full !self-stretch"
      @submit.prevent="submit"
    >
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.TRIGGERS.FORM.KIND_LABEL') }}
        </label>
        <Select v-model="triggerKind" :options="kindOptions" />
      </div>

      <div
        v-if="triggerKind === 'on_status_change'"
        class="flex flex-col gap-1"
      >
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.TRIGGERS.FORM.TARGET_STATUS_LABEL') }}
        </label>
        <Select v-model="targetStatus" :options="targetStatusOptions" />
      </div>

      <Input
        v-if="triggerKind === 'before_start'"
        v-model="offsetMinutes"
        type="number"
        min="1"
        :label="t('CALENDARIO.TRIGGERS.FORM.OFFSET_MINUTES_LABEL')"
      />

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.TRIGGERS.FORM.SERVICE_LABEL') }}
        </label>
        <Select v-model="serviceId" :options="serviceOptions" />
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.TRIGGERS.FORM.INBOX_LABEL') }}
        </label>
        <Select v-model="inboxId" :options="inboxOptions" />
      </div>

      <div v-if="inboxId" class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.TRIGGERS.FORM.TEMPLATE_LABEL') }}
        </label>
        <Select v-model="templateId" :options="templateOptions" />
        <p class="text-xs text-n-slate-10">
          {{ t('CALENDARIO.TRIGGERS.FORM.TEMPLATE_HINT') }}
        </p>
        <p
          v-if="inboxId && approvedTemplates.length === 0"
          class="text-xs text-n-ruby-9"
        >
          {{ t('CALENDARIO.TRIGGERS.FORM.NO_TEMPLATES') }}
        </p>
      </div>

      <WhatsAppTemplateParser
        v-if="selectedTemplate"
        ref="templateParserRef"
        :template="selectedTemplate"
      />

      <div class="flex items-center gap-2">
        <input id="trigger-active" v-model="active" type="checkbox" />
        <label for="trigger-active">
          {{ t('CALENDARIO.TRIGGERS.FORM.ACTIVE_LABEL') }}
        </label>
      </div>

      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          type="button"
          :label="t('CALENDARIO.TRIGGERS.FORM.CANCEL')"
          @click="onClose"
        />
        <Button
          type="submit"
          :label="
            isEditMode
              ? t('CALENDARIO.TRIGGERS.FORM.SAVE')
              : t('CALENDARIO.TRIGGERS.FORM.CREATE')
          "
          :is-loading="isSaving"
          :disabled="isFormInvalid"
        />
      </div>
    </form>
  </div>
</template>
