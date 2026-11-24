<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Select from 'dashboard/components-next/select/Select.vue';
import ConfirmButton from 'dashboard/components-next/button/ConfirmButton.vue';
import CalendarioWelcomeBotTriggerAPI from 'dashboard/api/calendarioWelcomeBotTrigger';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
  inboxId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const store = useStore();

const allFlows = useMapGetter('calendarioWelcomeBotFlows/getFlows');
const selectedFlowId = ref('');
const isSending = ref(false);

const flowOptions = computed(() => {
  const activeFlowsForInbox = allFlows.value.filter(
    flow => flow.active && String(flow.inbox_id) === String(props.inboxId)
  );
  return [
    {
      value: '',
      label: t('CALENDARIO.WELCOME_BOT_TRIGGER.SELECT_PLACEHOLDER'),
    },
    ...activeFlowsForInbox.map(flow => ({ value: flow.id, label: flow.name })),
  ];
});

const selectedFlow = computed(() =>
  allFlows.value.find(flow => flow.id === selectedFlowId.value)
);

// El primer paso casi siempre es el que de verdad importa: si no tiene
// content_sid (plantilla real aprobada), un envio de sesion libre fuera de
// la ventana de 24h de WhatsApp probablemente rebote -- se advierte, no se
// bloquea (puede que el paciente SI haya escrito hace poco).
const firstStepHasTemplate = computed(
  () => !!selectedFlow.value?.steps?.[0]?.content_sid
);

const sendFlow = async () => {
  isSending.value = true;
  try {
    await CalendarioWelcomeBotTriggerAPI.create({
      conversationId: props.conversationId,
      welcomeBotFlowId: selectedFlowId.value,
    });
    useAlert(t('CALENDARIO.WELCOME_BOT_TRIGGER.SUCCESS'));
    selectedFlowId.value = '';
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CALENDARIO.WELCOME_BOT_TRIGGER.ERROR')
    );
  } finally {
    isSending.value = false;
  }
};

onMounted(() => {
  if (!allFlows.value.length) store.dispatch('calendarioWelcomeBotFlows/get');
});
</script>

<template>
  <div class="flex flex-col gap-2 px-4 pt-3 pb-4">
    <p class="text-xs text-n-slate-11">
      {{ t('CALENDARIO.WELCOME_BOT_TRIGGER.DESCRIPTION') }}
    </p>
    <Select v-model="selectedFlowId" :options="flowOptions" />
    <p
      v-if="selectedFlowId && !firstStepHasTemplate"
      class="text-xs text-n-amber-11"
    >
      {{ t('CALENDARIO.WELCOME_BOT_TRIGGER.NO_TEMPLATE_WARNING') }}
    </p>
    <ConfirmButton
      v-if="selectedFlowId"
      size="sm"
      :label="t('CALENDARIO.WELCOME_BOT_TRIGGER.SEND_BUTTON')"
      :confirm-label="t('CALENDARIO.WELCOME_BOT_TRIGGER.SEND_CONFIRM')"
      :is-loading="isSending"
      @click="sendFlow"
    />
  </div>
</template>
