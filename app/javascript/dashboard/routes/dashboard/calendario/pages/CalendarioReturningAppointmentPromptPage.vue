<script setup>
import { computed, onMounted, reactive } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { isWhatsAppCapableInbox } from 'dashboard/helper/inbox';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const { t } = useI18n();
const store = useStore();

const allInboxes = useMapGetter('inboxes/getInboxes');
const getInbox = useMapGetter('inboxes/getInbox');
const whatsappInboxes = computed(() =>
  allInboxes.value.filter(isWhatsAppCapableInbox)
);

const configs = useMapGetter(
  'calendarioReturningAppointmentPromptConfigs/getConfigs'
);
const uiFlags = useMapGetter(
  'calendarioReturningAppointmentPromptConfigs/getUIFlags'
);

const DEFAULT_OPTIONS = [
  'Sí, cancelar cita',
  'Sí, reagendar',
  'Hablar con recepción',
];
const DEFAULT_ASK_TEMPLATE =
  'Hola nuevamente. Esta nueva solicitud es respecto de tu próxima cita ' +
  'el {{ appointment.date }} a las {{ appointment.time }} con {{ appointment.professional_name }} ' +
  '({{ appointment.service_name }}).';

// Un form reactivo por bandeja -- cada tarjeta se guarda de forma
// independiente, asi que no hace falta un modal aparte (son pocos campos y
// normalmente solo 1-2 bandejas de WhatsApp por cuenta).
const forms = reactive({});

const configForInbox = inboxId =>
  configs.value.find(config => config.inbox_id === inboxId);

const twilioTemplatesFor = inboxId => {
  const inboxRecord = getInbox.value(inboxId);
  return (inboxRecord?.content_templates?.templates || []).filter(
    template => template.status === 'approved'
  );
};

const ensureForm = inboxId => {
  if (forms[inboxId]) return;
  const existing = configForInbox(inboxId);
  forms[inboxId] = {
    id: existing?.id || null,
    active: existing?.active ?? false,
    testMode: existing?.test_mode ?? true,
    messageTemplateKey: existing?.message_template_key || '',
    askTemplate: existing?.ask_template || '',
    contentSid: existing?.content_sid || '',
    options: existing?.options?.length
      ? [...existing.options]
      : [...DEFAULT_OPTIONS],
    isSaving: false,
  };
};

const savePayload = form => ({
  active: form.active,
  test_mode: form.testMode,
  message_template_key: form.messageTemplateKey.trim(),
  ask_template: form.askTemplate.trim(),
  content_sid: form.contentSid,
  options: form.options.map(option => option.trim()).filter(Boolean),
});

const save = async inboxId => {
  const form = forms[inboxId];
  form.isSaving = true;
  try {
    if (form.id) {
      await store.dispatch(
        'calendarioReturningAppointmentPromptConfigs/update',
        {
          id: form.id,
          ...savePayload(form),
        }
      );
    } else {
      const created = await store.dispatch(
        'calendarioReturningAppointmentPromptConfigs/create',
        { inbox_id: inboxId, ...savePayload(form) }
      );
      form.id = created.id;
    }
    useAlert(t('CALENDARIO.RETURNING_PROMPT.SAVE_SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('CALENDARIO.RETURNING_PROMPT.SAVE_ERROR')
    );
  } finally {
    form.isSaving = false;
  }
};

onMounted(async () => {
  try {
    await Promise.all([
      store.dispatch('inboxes/get'),
      store.dispatch('calendarioReturningAppointmentPromptConfigs/get'),
    ]);
    whatsappInboxes.value.forEach(inbox => ensureForm(inbox.id));
  } catch (error) {
    useAlert(t('CALENDARIO.RETURNING_PROMPT.FETCH_ERROR'));
  }
});
</script>

<template>
  <div v-if="uiFlags.isFetching" class="flex items-center justify-center py-8">
    <Spinner />
  </div>
  <div v-else class="flex flex-col gap-4">
    <p class="text-sm text-n-slate-11 max-w-2xl">
      {{ t('CALENDARIO.RETURNING_PROMPT.DESCRIPTION') }}
    </p>

    <p
      v-if="!whatsappInboxes.length"
      class="text-sm text-n-slate-10 py-6 text-center"
    >
      {{ t('CALENDARIO.RETURNING_PROMPT.NO_INBOXES') }}
    </p>

    <div
      v-for="inbox in whatsappInboxes"
      :key="inbox.id"
      class="flex flex-col gap-3 rounded-lg border border-n-weak p-4"
    >
      <div v-if="forms[inbox.id]" class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-n-slate-12">{{
            inbox.name
          }}</span>
          <div class="flex items-center gap-2">
            <span class="text-xs text-n-slate-11">
              {{ t('CALENDARIO.RETURNING_PROMPT.ACTIVE_LABEL') }}
            </span>
            <Switch v-model="forms[inbox.id].active" />
          </div>
        </div>

        <div
          class="flex items-center justify-between rounded-lg px-3 py-2"
          :class="forms[inbox.id].testMode ? 'bg-n-amber-3' : 'bg-n-ruby-3'"
        >
          <div class="flex flex-col">
            <span class="text-xs font-medium text-n-slate-12">
              {{
                forms[inbox.id].testMode
                  ? t('CALENDARIO.RETURNING_PROMPT.TEST_MODE_ON')
                  : t('CALENDARIO.RETURNING_PROMPT.TEST_MODE_OFF')
              }}
            </span>
            <span class="text-[11px] text-n-slate-11">
              {{ t('CALENDARIO.RETURNING_PROMPT.TEST_MODE_HINT') }}
            </span>
          </div>
          <Switch v-model="forms[inbox.id].testMode" />
        </div>

        <Input
          v-model="forms[inbox.id].messageTemplateKey"
          :label="t('CALENDARIO.RETURNING_PROMPT.TEMPLATE_KEY_LABEL')"
          :placeholder="
            t('CALENDARIO.RETURNING_PROMPT.TEMPLATE_KEY_PLACEHOLDER')
          "
        />

        <TextArea
          v-model="forms[inbox.id].askTemplate"
          :label="t('CALENDARIO.RETURNING_PROMPT.ASK_TEMPLATE_LABEL')"
          :placeholder="DEFAULT_ASK_TEMPLATE"
          rows="3"
        />

        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CALENDARIO.RETURNING_PROMPT.TWILIO_TEMPLATE_LABEL') }}
          </label>
          <Select
            v-model="forms[inbox.id].contentSid"
            :options="[
              {
                value: '',
                label: t('CALENDARIO.RETURNING_PROMPT.TEMPLATE_PLACEHOLDER'),
              },
              ...twilioTemplatesFor(inbox.id).map(template => ({
                value: template.content_sid,
                label: `${template.friendly_name} (${template.language || ''}) · ${template.category || '?'}`,
              })),
            ]"
          />
          <p class="text-xs text-n-slate-10">
            {{ t('CALENDARIO.RETURNING_PROMPT.TWILIO_TEMPLATE_HINT') }}
          </p>
        </div>

        <div class="flex flex-col gap-1">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CALENDARIO.RETURNING_PROMPT.OPTIONS_LABEL') }}
          </label>
          <div class="flex flex-col gap-1.5">
            <Input
              v-for="(option, index) in forms[inbox.id].options"
              :key="index"
              v-model="forms[inbox.id].options[index]"
            />
          </div>
        </div>

        <div class="flex justify-end">
          <Button
            size="sm"
            :is-loading="forms[inbox.id].isSaving"
            :label="t('CALENDARIO.RETURNING_PROMPT.SAVE_BUTTON')"
            @click="save(inbox.id)"
          />
        </div>
      </div>
    </div>
  </div>
</template>
