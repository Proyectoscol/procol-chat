<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { isWhatsAppCapableInbox } from 'dashboard/helper/inbox';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  flow: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const { t, locale } = useI18n();

// Fuera de t() a proposito -- vue-i18n interpreta "{{ ... }}" como su propia
// sintaxis de interpolacion (ver STEP_ASK_TEMPLATE_HINT, que describe esto
// sin llaves literales), asi que un placeholder de ejemplo con llaves
// dobles de Liquid reales rompe el compilador de mensajes si se pasa por
// t(). Un string plano no tiene ese problema.
const askTemplatePlaceholder = computed(() =>
  locale.value === 'es'
    ? '¿Te refieres a tu cita del {{ appointment.date }} a las {{ appointment.time }} con {{ appointment.professional_name }} ({{ appointment.service_name }})?'
    : 'Are you referring to your appointment on {{ appointment.date }} at {{ appointment.time }} with {{ appointment.professional_name }} ({{ appointment.service_name }})?'
);
const store = useStore();

const allInboxes = useMapGetter('inboxes/getInboxes');
const whatsappInboxes = computed(() =>
  allInboxes.value.filter(isWhatsAppCapableInbox)
);
const getInbox = useMapGetter('inboxes/getInbox');

const isEditMode = computed(() => !!props.flow);

const name = ref('');
const inboxId = ref('');

// Catalogo de plantillas reales de Twilio ya sincronizado para la bandeja
// elegida (Twilio::TemplateSyncService) -- vacio para bandejas Meta, que no
// tienen esta columna. Permite mandar un quick-reply real de WhatsApp en
// vez de texto plano (ver Calendario::WelcomeBotFlowRunner#send_whatsapp_buttons).
const twilioTemplates = computed(() => {
  if (!inboxId.value) return [];
  const inboxRecord = getInbox.value(inboxId.value);
  return (inboxRecord?.content_templates?.templates || []).filter(
    template => template.status === 'approved'
  );
});

const matchType = ref('default');
const matchValue = ref('');
const priority = ref(0);
const active = ref(true);
const escalationMessage = ref('');
const isSaving = ref(false);

// Cada paso en memoria guarda las opciones como texto (una por linea) para
// que el textarea sea editable sin reconstruir el array en cada tecla --
// se parte a un array real solo al enviar (ver stepsForSubmit).
const steps = ref([]);

// Si tiene condicion, en memoria vive como { enabled, stepIndex, equals }
// en vez del {step, equals} crudo que espera el backend -- mas facil de
// atar a los selects del formulario; se reconstruye al enviar.
//
// "type" decide que campos se muestran/envian -- ver STEP_TYPE_OPTIONS y
// Calendario::WelcomeBotFlow (comentario de esquema) para el significado
// de cada tipo. Los campos de los tipos no usados quedan vacios en memoria
// sin problema, nunca se envian si no aplican (ver stepsForSubmit).
const makeStep = () => ({
  type: 'ask',
  ask: '',
  optionsText: '',
  askTemplate: '',
  askTemplateKey: '',
  emptyMessage: '',
  emptyMessageKey: '',
  waitlistKeyword: '',
  ackMessage: '',
  ackMessageKey: '',
  contentSid: '',
  condition: { enabled: false, stepIndex: 0, equals: '' },
});

// Solo estos tipos mandan una pregunta/mensaje con opciones -- los de
// accion (cancelar/reagendar/transferir) nunca llegan a
// WelcomeBotFlowRunner#send_whatsapp_buttons, asi que un content_sid ahi
// seria ignorado silenciosamente por el backend.
const STEP_TYPES_WITH_OPTIONS = ['ask', 'lookup_appointment'];

// Un recordatorio es { afterMinutes, message } -- el ultimo de la lista
// siempre escala a un agente humano (ver BotSessionReminderJob). Vacio por
// defecto = usar el comportamiento historico (5min/20min) del backend.
const makeReminder = () => ({ afterMinutes: '', message: '' });
const reminders = ref([]);
const addReminder = () => reminders.value.push(makeReminder());
const removeReminder = index => reminders.value.splice(index, 1);

const setFormValues = () => {
  name.value = props.flow?.name || '';
  inboxId.value = props.flow?.inbox_id || '';
  matchType.value = props.flow?.match_type || 'default';
  matchValue.value = props.flow?.match_value || '';
  priority.value = props.flow?.priority ?? 0;
  active.value = props.flow ? props.flow.active : true;
  escalationMessage.value = props.flow?.escalation_message || '';
  steps.value = (props.flow?.steps || []).map(step => ({
    type: step.type || 'ask',
    ask: step.ask || '',
    optionsText: (step.options || step.buttons || []).join('\n'),
    askTemplate: step.ask_template || '',
    askTemplateKey: step.ask_template_key || '',
    emptyMessage: step.empty_message || '',
    emptyMessageKey: step.empty_message_key || '',
    waitlistKeyword: step.waitlist_keyword || '',
    ackMessage: step.ack_message || '',
    ackMessageKey: step.ack_message_key || '',
    contentSid: step.content_sid || '',
    condition: step.if
      ? { enabled: true, stepIndex: step.if.step, equals: step.if.equals }
      : { enabled: false, stepIndex: 0, equals: '' },
  }));
  if (!steps.value.length) steps.value.push(makeStep());

  reminders.value = (props.flow?.reminder_schedule || []).map(entry => ({
    afterMinutes: entry.after_minutes ?? '',
    message: entry.message || '',
  }));
};
watch(() => props.flow, setFormValues, { immediate: true });

onMounted(() => {
  store.dispatch('inboxes/get');
});

const matchTypeOptions = computed(() => [
  {
    value: 'default',
    label: t('CALENDARIO.WELCOME_BOT.FORM.MATCH_TYPE_OPTIONS.DEFAULT'),
  },
  {
    value: 'keyword',
    label: t('CALENDARIO.WELCOME_BOT.FORM.MATCH_TYPE_OPTIONS.KEYWORD'),
  },
]);

const stepTypeOptions = computed(() => [
  {
    value: 'ask',
    label: t('CALENDARIO.WELCOME_BOT.FORM.STEP_TYPE_OPTIONS.ASK'),
  },
  {
    value: 'lookup_appointment',
    label: t(
      'CALENDARIO.WELCOME_BOT.FORM.STEP_TYPE_OPTIONS.LOOKUP_APPOINTMENT'
    ),
  },
  {
    value: 'perform_cancellation',
    label: t(
      'CALENDARIO.WELCOME_BOT.FORM.STEP_TYPE_OPTIONS.PERFORM_CANCELLATION'
    ),
  },
  {
    value: 'request_reschedule',
    label: t(
      'CALENDARIO.WELCOME_BOT.FORM.STEP_TYPE_OPTIONS.REQUEST_RESCHEDULE'
    ),
  },
  {
    value: 'handoff',
    label: t('CALENDARIO.WELCOME_BOT.FORM.STEP_TYPE_OPTIONS.HANDOFF'),
  },
]);

const inboxOptions = computed(() => [
  { value: '', label: t('CALENDARIO.WELCOME_BOT.FORM.INBOX_PLACEHOLDER') },
  ...whatsappInboxes.value.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  })),
]);

const addStep = () => {
  steps.value.push(makeStep());
};
const removeStep = index => {
  steps.value.splice(index, 1);
  // Cualquier condicion que apuntara a un paso borrado (o posterior, que
  // cambio de indice) queda inconsistente -- se desactiva, el usuario la
  // vuelve a armar si todavia aplica.
  steps.value.forEach(step => {
    if (
      step.condition.enabled &&
      step.condition.stepIndex >= steps.value.length
    ) {
      step.condition.enabled = false;
    }
  });
};

// Las opciones del paso referenciado por la condicion -- si existen, se
// ofrecen como select en vez de que el usuario tenga que escribir el valor
// exacto a mano (y arriesgarse a un typo que nunca matchee).
const conditionOptionsFor = stepIndex => {
  const referenced = steps.value[stepIndex];
  if (!referenced) return [];
  return referenced.optionsText
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean);
};

// El <select> de "equals" muestra la primera opcion seleccionada por
// comportamiento nativo del navegador incluso cuando el v-model sigue en ''
// -- sin esto el valor guardado queda vacio aunque se vea una opcion marcada.
watch(
  steps,
  newSteps => {
    newSteps.forEach(step => {
      if (!step.condition.enabled) return;
      const options = conditionOptionsFor(step.condition.stepIndex);
      if (options.length && !options.includes(step.condition.equals)) {
        step.condition.equals = options[0];
      }
    });
  },
  { deep: true }
);

const isFormInvalid = computed(() => {
  if (!name.value.trim() || !inboxId.value) return true;
  if (matchType.value === 'keyword' && !matchValue.value.trim()) return true;
  if (!steps.value.length) return true;
  // Solo "ask" necesita texto propio -- los demas tipos tienen defaults en
  // el backend si se dejan en blanco (ver Calendario::WelcomeBotAppointmentActions).
  return steps.value.some(step => step.type === 'ask' && !step.ask.trim());
});

// Si el paso ya tenia guardado un content_sid que ya no aparece como
// aprobado en el catalogo (ej. nunca se sometio a Meta, o se reclasifico),
// se agrega igual como opcion marcada -- sin esto el <select> lo mostraria
// en blanco (value sin match en la lista) y daria la falsa impresion de que
// el paso no tiene botones reales configurados.
const contentSidOptionsFor = step => {
  const options = [
    {
      value: '',
      label: t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONTENT_SID_PLACEHOLDER'),
    },
    ...twilioTemplates.value.map(template => ({
      value: template.content_sid,
      // category visible en la etiqueta -- MARKETING corre riesgo real de
      // que Meta decida no entregarla (ver hallazgo del 2026-11-20), asi
      // que no debe quedar oculto dentro de un dropdown.
      label: `${template.friendly_name} (${template.language || ''}) · ${template.category || '?'}`,
    })),
  ];
  const isCurrentValueListed = options.some(
    option => option.value === step.contentSid
  );
  if (step.contentSid && !isCurrentValueListed) {
    options.push({
      value: step.contentSid,
      label: t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONTENT_SID_UNKNOWN', {
        contentSid: step.contentSid,
      }),
    });
  }
  return options;
};

const stepOptionsFor = step =>
  step.optionsText
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean);

const stepsForSubmit = () =>
  steps.value.map(step => {
    const payload = { type: step.type };
    const options = stepOptionsFor(step);

    if (step.type === 'ask') {
      payload.ask = step.ask.trim();
    }
    if (STEP_TYPES_WITH_OPTIONS.includes(step.type) && options.length) {
      payload.options = options;
    }
    if (STEP_TYPES_WITH_OPTIONS.includes(step.type) && step.contentSid) {
      payload.content_sid = step.contentSid;
    }
    if (step.type === 'lookup_appointment') {
      if (step.askTemplate.trim())
        payload.ask_template = step.askTemplate.trim();
      if (step.askTemplateKey.trim())
        payload.ask_template_key = step.askTemplateKey.trim();
      if (step.emptyMessage.trim())
        payload.empty_message = step.emptyMessage.trim();
      if (step.emptyMessageKey.trim())
        payload.empty_message_key = step.emptyMessageKey.trim();
    }
    if (step.type === 'perform_cancellation' && step.waitlistKeyword.trim()) {
      payload.waitlist_keyword = step.waitlistKeyword.trim();
    }
    if (['request_reschedule', 'handoff'].includes(step.type)) {
      if (step.ackMessage.trim()) payload.ack_message = step.ackMessage.trim();
      if (step.ackMessageKey.trim())
        payload.ack_message_key = step.ackMessageKey.trim();
    }
    if (step.condition.enabled) {
      payload.if = {
        step: step.condition.stepIndex,
        equals: step.condition.equals,
      };
    }
    return payload;
  });

const reminderScheduleForSubmit = () =>
  reminders.value
    .filter(r => Number(r.afterMinutes) > 0)
    .map(r => ({
      after_minutes: Number(r.afterMinutes),
      message: r.message.trim(),
    }));

const onClose = () => emit('close');

const submit = async () => {
  isSaving.value = true;
  const payload = {
    name: name.value.trim(),
    inbox_id: inboxId.value,
    match_type: matchType.value,
    match_value: matchType.value === 'keyword' ? matchValue.value.trim() : null,
    priority: Number(priority.value),
    active: active.value,
    escalation_message: escalationMessage.value.trim(),
    steps: stepsForSubmit(),
    reminder_schedule: reminderScheduleForSubmit(),
  };
  try {
    if (isEditMode.value) {
      await store.dispatch('calendarioWelcomeBotFlows/update', {
        id: props.flow.id,
        ...payload,
      });
      useAlert(t('CALENDARIO.WELCOME_BOT.FORM.EDIT_SUCCESS'));
    } else {
      await store.dispatch('calendarioWelcomeBotFlows/create', payload);
      useAlert(t('CALENDARIO.WELCOME_BOT.FORM.CREATE_SUCCESS'));
    }
    onClose();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CALENDARIO.WELCOME_BOT.FORM.ERROR')
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
          ? t('CALENDARIO.WELCOME_BOT.FORM.EDIT_TITLE')
          : t('CALENDARIO.WELCOME_BOT.FORM.CREATE_TITLE')
      "
    />
    <form
      class="flex flex-col gap-4 px-4 pb-4 w-full !self-stretch"
      @submit.prevent="submit"
    >
      <Input
        v-model="name"
        :label="t('CALENDARIO.WELCOME_BOT.FORM.NAME_LABEL')"
      />

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.WELCOME_BOT.FORM.INBOX_LABEL') }}
        </label>
        <Select v-model="inboxId" :options="inboxOptions" />
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.WELCOME_BOT.FORM.MATCH_TYPE_LABEL') }}
        </label>
        <Select v-model="matchType" :options="matchTypeOptions" />
        <p class="text-xs text-n-slate-10">
          {{ t('CALENDARIO.WELCOME_BOT.FORM.MATCH_TYPE_HINT') }}
        </p>
      </div>

      <Input
        v-if="matchType === 'keyword'"
        v-model="matchValue"
        :label="t('CALENDARIO.WELCOME_BOT.FORM.MATCH_VALUE_LABEL')"
        :placeholder="t('CALENDARIO.WELCOME_BOT.FORM.MATCH_VALUE_PLACEHOLDER')"
      />

      <Input
        v-model="priority"
        type="number"
        :label="t('CALENDARIO.WELCOME_BOT.FORM.PRIORITY_LABEL')"
      />
      <p class="text-xs text-n-slate-10 -mt-3">
        {{ t('CALENDARIO.WELCOME_BOT.FORM.PRIORITY_HINT') }}
      </p>

      <div class="flex flex-col gap-3">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.WELCOME_BOT.FORM.STEPS_LABEL') }}
        </label>

        <div
          v-for="(step, index) in steps"
          :key="index"
          class="flex flex-col gap-2 rounded-lg border border-n-weak p-3"
        >
          <div class="flex items-center justify-between">
            <span class="text-xs font-medium text-n-slate-11">
              {{
                t('CALENDARIO.WELCOME_BOT.FORM.STEP_NUMBER', {
                  number: index + 1,
                })
              }}
            </span>
            <Button
              v-if="steps.length > 1"
              icon="i-woot-bin"
              slate
              sm
              type="button"
              @click="removeStep(index)"
            />
          </div>

          <div class="flex flex-col gap-1">
            <label class="text-xs font-medium text-n-slate-11">
              {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_TYPE_LABEL') }}
            </label>
            <Select v-model="step.type" :options="stepTypeOptions" />
          </div>

          <Input
            v-if="step.type === 'ask'"
            v-model="step.ask"
            :label="t('CALENDARIO.WELCOME_BOT.FORM.STEP_ASK_LABEL')"
          />

          <template v-if="step.type === 'lookup_appointment'">
            <TextArea
              v-model="step.askTemplate"
              :label="t('CALENDARIO.WELCOME_BOT.FORM.STEP_ASK_TEMPLATE_LABEL')"
              :placeholder="askTemplatePlaceholder"
            />
            <p class="text-xs text-n-slate-10 -mt-1">
              {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_ASK_TEMPLATE_HINT') }}
            </p>
            <Input
              v-model="step.askTemplateKey"
              :label="t('CALENDARIO.WELCOME_BOT.FORM.STEP_TEMPLATE_KEY_LABEL')"
              :placeholder="
                t('CALENDARIO.WELCOME_BOT.FORM.STEP_TEMPLATE_KEY_PLACEHOLDER')
              "
            />
            <p class="text-xs text-n-slate-10 -mt-1">
              {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_TEMPLATE_KEY_HINT') }}
            </p>
            <p class="text-xs text-n-slate-10">
              {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_LOOKUP_OPTIONS_HINT') }}
            </p>
            <TextArea
              v-model="step.emptyMessage"
              :label="t('CALENDARIO.WELCOME_BOT.FORM.STEP_EMPTY_MESSAGE_LABEL')"
              :placeholder="
                t('CALENDARIO.WELCOME_BOT.FORM.STEP_EMPTY_MESSAGE_PLACEHOLDER')
              "
            />
            <Input
              v-model="step.emptyMessageKey"
              :label="t('CALENDARIO.WELCOME_BOT.FORM.STEP_TEMPLATE_KEY_LABEL')"
              :placeholder="
                t('CALENDARIO.WELCOME_BOT.FORM.STEP_TEMPLATE_KEY_PLACEHOLDER')
              "
            />
          </template>

          <TextArea
            v-if="STEP_TYPES_WITH_OPTIONS.includes(step.type)"
            v-model="step.optionsText"
            :label="t('CALENDARIO.WELCOME_BOT.FORM.STEP_OPTIONS_LABEL')"
            :placeholder="
              t('CALENDARIO.WELCOME_BOT.FORM.STEP_OPTIONS_PLACEHOLDER')
            "
          />

          <div
            v-if="STEP_TYPES_WITH_OPTIONS.includes(step.type)"
            class="flex flex-col gap-1"
          >
            <label class="text-xs font-medium text-n-slate-11">
              {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONTENT_SID_LABEL') }}
            </label>
            <Select
              v-model="step.contentSid"
              :options="contentSidOptionsFor(step)"
            />
            <p class="text-xs text-n-slate-10">
              {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONTENT_SID_HINT') }}
            </p>
            <p
              v-if="inboxId && twilioTemplates.length === 0"
              class="text-xs text-n-ruby-9"
            >
              {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONTENT_SID_EMPTY') }}
            </p>
            <p
              v-if="
                step.contentSid &&
                !twilioTemplates.some(t2 => t2.content_sid === step.contentSid)
              "
              class="text-xs text-n-ruby-9"
            >
              {{
                t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONTENT_SID_NOT_APPROVED')
              }}
            </p>
          </div>

          <template v-if="step.type === 'perform_cancellation'">
            <Input
              v-model="step.waitlistKeyword"
              :label="
                t('CALENDARIO.WELCOME_BOT.FORM.STEP_WAITLIST_KEYWORD_LABEL')
              "
              placeholder="lista de espera"
            />
            <p class="text-xs text-n-slate-10 -mt-1">
              {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_WAITLIST_KEYWORD_HINT') }}
            </p>
          </template>

          <template
            v-if="['request_reschedule', 'handoff'].includes(step.type)"
          >
            <TextArea
              v-model="step.ackMessage"
              :label="t('CALENDARIO.WELCOME_BOT.FORM.STEP_ACK_MESSAGE_LABEL')"
              :placeholder="
                t('CALENDARIO.WELCOME_BOT.FORM.STEP_ACK_MESSAGE_PLACEHOLDER')
              "
            />
            <Input
              v-model="step.ackMessageKey"
              :label="t('CALENDARIO.WELCOME_BOT.FORM.STEP_TEMPLATE_KEY_LABEL')"
              :placeholder="
                t('CALENDARIO.WELCOME_BOT.FORM.STEP_TEMPLATE_KEY_PLACEHOLDER')
              "
            />
          </template>

          <div
            v-if="index > 0"
            class="flex flex-col gap-2 border-t border-n-weak pt-2"
          >
            <div class="flex items-center gap-2">
              <input
                :id="`step-condition-${index}`"
                v-model="step.condition.enabled"
                type="checkbox"
              />
              <label
                :for="`step-condition-${index}`"
                class="text-xs text-n-slate-11"
              >
                {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONDITION_LABEL') }}
              </label>
            </div>

            <div
              v-if="step.condition.enabled"
              class="flex flex-wrap items-center gap-2 pl-5"
            >
              <span class="text-xs text-n-slate-11">
                {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONDITION_IF') }}
              </span>
              <Select
                v-model="step.condition.stepIndex"
                :options="
                  Array.from({ length: index }, (_, i) => ({
                    value: i,
                    label: t('CALENDARIO.WELCOME_BOT.FORM.STEP_NUMBER', {
                      number: i + 1,
                    }),
                  }))
                "
              />
              <span class="text-xs text-n-slate-11">
                {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONDITION_EQUALS') }}
              </span>
              <Select
                v-if="conditionOptionsFor(step.condition.stepIndex).length"
                v-model="step.condition.equals"
                :options="
                  conditionOptionsFor(step.condition.stepIndex).map(value => ({
                    value,
                    label: value,
                  }))
                "
              />
              <Input v-else v-model="step.condition.equals" class="!mb-0" />
            </div>
          </div>
        </div>

        <Button
          faded
          slate
          sm
          type="button"
          icon="i-lucide-plus"
          :label="t('CALENDARIO.WELCOME_BOT.FORM.ADD_STEP_BUTTON')"
          @click="addStep"
        />
      </div>

      <TextArea
        v-model="escalationMessage"
        :label="t('CALENDARIO.WELCOME_BOT.FORM.ESCALATION_MESSAGE_LABEL')"
        :placeholder="
          t('CALENDARIO.WELCOME_BOT.FORM.ESCALATION_MESSAGE_PLACEHOLDER')
        "
      />
      <p class="text-xs text-n-slate-10 -mt-3">
        {{ t('CALENDARIO.WELCOME_BOT.FORM.ESCALATION_MESSAGE_HINT') }}
      </p>

      <div class="flex flex-col gap-3">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.WELCOME_BOT.FORM.REMINDER_SCHEDULE_LABEL') }}
        </label>
        <p class="text-xs text-n-slate-10 -mt-2">
          {{ t('CALENDARIO.WELCOME_BOT.FORM.REMINDER_SCHEDULE_HINT') }}
        </p>

        <div
          v-for="(reminder, index) in reminders"
          :key="index"
          class="flex flex-col gap-2 rounded-lg border border-n-weak p-3"
        >
          <div class="flex items-center justify-between">
            <span class="text-xs font-medium text-n-slate-11">
              {{
                t('CALENDARIO.WELCOME_BOT.FORM.REMINDER_NUMBER', {
                  number: index + 1,
                })
              }}
              <template v-if="index === reminders.length - 1">
                {{ t('CALENDARIO.WELCOME_BOT.FORM.REMINDER_LAST_HINT') }}
              </template>
            </span>
            <Button
              icon="i-woot-bin"
              slate
              sm
              type="button"
              @click="removeReminder(index)"
            />
          </div>
          <Input
            v-model="reminder.afterMinutes"
            type="number"
            :label="
              t('CALENDARIO.WELCOME_BOT.FORM.REMINDER_AFTER_MINUTES_LABEL')
            "
          />
          <TextArea
            v-model="reminder.message"
            :label="t('CALENDARIO.WELCOME_BOT.FORM.REMINDER_MESSAGE_LABEL')"
            :placeholder="
              t('CALENDARIO.WELCOME_BOT.FORM.REMINDER_MESSAGE_PLACEHOLDER')
            "
          />
        </div>

        <Button
          faded
          slate
          sm
          type="button"
          icon="i-lucide-plus"
          :label="t('CALENDARIO.WELCOME_BOT.FORM.ADD_REMINDER_BUTTON')"
          @click="addReminder"
        />
      </div>

      <div class="flex items-center gap-2">
        <input id="flow-active" v-model="active" type="checkbox" />
        <label for="flow-active">{{
          t('CALENDARIO.WELCOME_BOT.FORM.ACTIVE_LABEL')
        }}</label>
      </div>

      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          type="button"
          :label="t('CALENDARIO.WELCOME_BOT.FORM.CANCEL')"
          @click="onClose"
        />
        <Button
          type="submit"
          :label="
            isEditMode
              ? t('CALENDARIO.WELCOME_BOT.FORM.SAVE')
              : t('CALENDARIO.WELCOME_BOT.FORM.CREATE')
          "
          :is-loading="isSaving"
          :disabled="isFormInvalid"
        />
      </div>
    </form>
  </div>
</template>
