<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { INBOX_TYPES, isWhatsAppCapableInbox } from 'dashboard/helper/inbox';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Textarea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

const props = defineProps({
  trigger: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const allInboxes = useMapGetter('inboxes/getInboxes');
const whatsappInboxes = computed(() =>
  allInboxes.value.filter(isWhatsAppCapableInbox)
);
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

const PAYER_KINDS = [
  'particular',
  'eps',
  'plan_complementario',
  'prepagada',
  'poliza',
];

const triggerKind = ref('on_create');
const targetStatus = ref('');
const offsetMinutes = ref('');
const serviceIds = ref([]);
const payerKinds = ref([]);
const inboxId = ref('');
const templateId = ref('');
const active = ref(true);
const testMode = ref(false);
const isSaving = ref(false);
const templateParserRef = ref(null);
const customBody = ref('');

// Las bandejas de Twilio con medium whatsapp no tienen catalogo de
// plantillas aprobadas por Meta (ver inboxes.js#getWhatsAppInboxes) -- para
// esas, en vez del selector de plantillas se escribe el texto a mano y el
// disparador queda forzado a test_mode (nunca hay una plantilla real que
// mandarle a la API de Twilio).
const selectedInbox = computed(() =>
  whatsappInboxes.value.find(
    inbox => String(inbox.id) === String(inboxId.value)
  )
);
const selectedInboxIsMetaWhatsapp = computed(
  () => selectedInbox.value?.channel_type === INBOX_TYPES.WHATSAPP
);

const setFormValues = () => {
  triggerKind.value = props.trigger?.trigger_kind || 'on_create';
  targetStatus.value = props.trigger?.target_status || '';
  offsetMinutes.value = props.trigger?.offset_minutes ?? '';
  serviceIds.value = props.trigger?.service_ids ?? [];
  payerKinds.value = props.trigger?.payer_kinds ?? [];
  inboxId.value = props.trigger?.inbox_id ?? '';
  active.value = props.trigger ? props.trigger.active : true;
  testMode.value = props.trigger ? !!props.trigger.test_mode : false;
  customBody.value =
    props.trigger?.template_params?.processed_params?.body ?? '';
  // La plantilla elegida se resuelve de nuevo por nombre+idioma una vez
  // carguen los templates del inbox (ver watch de inboxId más abajo);
  // no se puede resolver aquí porque todavía no sabemos el id interno.
  templateId.value = '';
};
watch(() => props.trigger, setFormValues, { immediate: true });

// Si la bandeja elegida no tiene plantillas reales, no tiene sentido
// mandar un mensaje real -- se fuerza y bloquea test_mode.
watch(
  selectedInboxIsMetaWhatsapp,
  isMeta => {
    if (!isMeta) testMode.value = true;
  },
  { immediate: true }
);

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
  {
    value: 'on_reschedule',
    label: t('CALENDARIO.TRIGGERS.FORM.KIND_OPTIONS.ON_RESCHEDULE'),
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

const payerKindOptions = computed(() =>
  PAYER_KINDS.map(kind => ({
    value: kind,
    label: t(`CALENDARIO.PAYERS.KIND_VALUES.${kind.toUpperCase()}`),
  }))
);

const toggleInArray = (arrayRef, value) => {
  const index = arrayRef.value.indexOf(value);
  if (index === -1) {
    arrayRef.value = [...arrayRef.value, value];
  } else {
    arrayRef.value = arrayRef.value.filter(item => item !== value);
  }
};
const toggleService = id => toggleInArray(serviceIds, id);
const togglePayerKind = kind => toggleInArray(payerKinds, kind);

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
  if (!inboxId.value) return true;
  if (selectedInboxIsMetaWhatsapp.value) {
    if (!templateId.value) return true;
  } else if (!customBody.value.trim()) {
    return true;
  }
  if (triggerKind.value === 'on_status_change' && !targetStatus.value) {
    return true;
  }
  if (triggerKind.value === 'before_start' && !offsetMinutes.value) {
    return true;
  }
  return false;
});

const onClose = () => emit('close');

// before_start: minutos ANTES, obligatorio (validado arriba en isFormInvalid).
// on_status_change: minutos DESPUES, opcional -- vacio = 0 = instantaneo
// (ver Calendario::AppointmentEventTrigger#delay_minutes en el backend).
const offsetMinutesForSubmit = () => {
  if (triggerKind.value === 'before_start') return Number(offsetMinutes.value);
  if (triggerKind.value === 'on_status_change') {
    return offsetMinutes.value === '' ? null : Number(offsetMinutes.value);
  }
  return null;
};

const submit = async () => {
  let templateParams;
  if (selectedInboxIsMetaWhatsapp.value) {
    if (!selectedTemplate.value) return;
    templateParserRef.value?.v$?.$touch();
    if (templateParserRef.value?.v$?.$invalid) return;

    const { name, category, language, namespace } = selectedTemplate.value;
    templateParams = {
      name,
      category,
      language,
      namespace,
      processed_params: templateParserRef.value?.processedParams || {},
    };
  } else {
    // Bandeja sin catalogo de plantillas de Meta (ej. Twilio): texto libre,
    // siempre en test_mode -- ver watch de selectedInboxIsMetaWhatsapp.
    templateParams = {
      name: 'custom_test',
      category: 'custom',
      language: null,
      namespace: null,
      processed_params: { body: customBody.value },
    };
  }

  isSaving.value = true;
  const payload = {
    trigger_kind: triggerKind.value,
    target_status:
      triggerKind.value === 'on_status_change' ? targetStatus.value : null,
    offset_minutes: offsetMinutesForSubmit(),
    service_ids: serviceIds.value,
    payer_kinds: payerKinds.value,
    inbox_id: inboxId.value,
    active: active.value,
    test_mode: testMode.value,
    template_params: templateParams,
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

      <div
        v-if="triggerKind === 'on_status_change'"
        class="flex flex-col gap-1"
      >
        <Input
          v-model="offsetMinutes"
          type="number"
          min="0"
          :label="t('CALENDARIO.TRIGGERS.FORM.DELAY_MINUTES_LABEL')"
          :placeholder="t('CALENDARIO.TRIGGERS.FORM.DELAY_MINUTES_PLACEHOLDER')"
        />
        <p class="text-xs text-n-slate-10">
          {{ t('CALENDARIO.TRIGGERS.FORM.DELAY_MINUTES_HINT') }}
        </p>
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.TRIGGERS.FORM.SERVICE_LABEL') }}
        </label>
        <div
          class="grid grid-cols-2 gap-x-3 gap-y-1 p-2 border rounded-lg border-n-weak max-h-40 overflow-y-auto"
        >
          <div
            v-for="service in services"
            :key="service.id"
            class="flex items-center gap-2"
          >
            <input
              :id="`trigger-service-${service.id}`"
              type="checkbox"
              :checked="serviceIds.includes(service.id)"
              @change="toggleService(service.id)"
            />
            <label
              :for="`trigger-service-${service.id}`"
              class="text-sm text-n-slate-12"
            >
              {{ service.name }}
            </label>
          </div>
        </div>
        <p class="text-xs text-n-slate-10">
          {{ t('CALENDARIO.TRIGGERS.FORM.SERVICE_HINT') }}
        </p>
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.TRIGGERS.FORM.PAYER_KIND_LABEL') }}
        </label>
        <div
          class="grid grid-cols-2 gap-x-3 gap-y-1 p-2 border rounded-lg border-n-weak"
        >
          <div
            v-for="option in payerKindOptions"
            :key="option.value"
            class="flex items-center gap-2"
          >
            <input
              :id="`trigger-payer-kind-${option.value}`"
              type="checkbox"
              :checked="payerKinds.includes(option.value)"
              @change="togglePayerKind(option.value)"
            />
            <label
              :for="`trigger-payer-kind-${option.value}`"
              class="text-sm text-n-slate-12"
            >
              {{ option.label }}
            </label>
          </div>
        </div>
        <p class="text-xs text-n-slate-10">
          {{ t('CALENDARIO.TRIGGERS.FORM.PAYER_KIND_HINT') }}
        </p>
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.TRIGGERS.FORM.INBOX_LABEL') }}
        </label>
        <Select v-model="inboxId" :options="inboxOptions" />
      </div>

      <div
        v-if="inboxId && selectedInboxIsMetaWhatsapp"
        class="flex flex-col gap-1"
      >
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
        v-if="selectedInboxIsMetaWhatsapp && selectedTemplate"
        ref="templateParserRef"
        :template="selectedTemplate"
      />

      <!-- Bandejas de Twilio (medium whatsapp) no tienen catalogo de
      plantillas aprobadas por Meta: el texto se escribe a mano y el envio
      queda forzado a nota privada de prueba (ver watch de
      selectedInboxIsMetaWhatsapp). -->
      <div
        v-if="inboxId && !selectedInboxIsMetaWhatsapp"
        class="flex flex-col gap-1"
      >
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.TRIGGERS.FORM.CUSTOM_BODY_LABEL') }}
        </label>
        <Textarea
          v-model="customBody"
          auto-height
          min-height="6rem"
          :placeholder="t('CALENDARIO.TRIGGERS.FORM.CUSTOM_BODY_PLACEHOLDER')"
        />
        <p class="text-xs text-n-slate-10">
          {{ t('CALENDARIO.TRIGGERS.FORM.CUSTOM_BODY_HINT') }}
        </p>
      </div>

      <div class="flex items-center gap-2">
        <input id="trigger-active" v-model="active" type="checkbox" />
        <label for="trigger-active">
          {{ t('CALENDARIO.TRIGGERS.FORM.ACTIVE_LABEL') }}
        </label>
      </div>

      <!-- Pedido explicito del usuario antes de pasar a produccion: poder
      probar como queda el mensaje sin mandarlo de verdad por WhatsApp. -->
      <div
        class="flex items-start gap-2 rounded-lg border border-n-amber-5 bg-n-amber-2 p-3"
      >
        <input
          id="trigger-test-mode"
          v-model="testMode"
          type="checkbox"
          class="mt-0.5"
          :disabled="!selectedInboxIsMetaWhatsapp"
        />
        <label for="trigger-test-mode" class="flex flex-col gap-0.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('CALENDARIO.TRIGGERS.FORM.TEST_MODE_LABEL') }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{
              selectedInboxIsMetaWhatsapp
                ? t('CALENDARIO.TRIGGERS.FORM.TEST_MODE_HINT')
                : t('CALENDARIO.TRIGGERS.FORM.TEST_MODE_FORCED_HINT')
            }}
          </span>
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
