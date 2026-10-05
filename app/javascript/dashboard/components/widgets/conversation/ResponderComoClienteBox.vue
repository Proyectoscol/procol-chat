<!-- Entorno de pruebas de Cartera: permite a un administrador escribir como
si fuera el cliente dentro de una conversacion de la bandeja de pruebas
(Channel::Api), para verificar en vivo que responde/escala/guarda el Agente
IA. Solo visible si la bandeja de la conversacion actual es tipo API -
Messages::MessageBuilder#message_type (app/builders/messages/message_builder.rb)
ya rechaza message_type: incoming en cualquier otro tipo de bandeja, asi que
este componente nunca puede enviar un mensaje "como cliente" contra un canal
real. Deliberadamente separado de ReplyBox.vue (el composer real de
agentes) en vez de extenderlo, para no tocar ese componente compartido de
1600+ lineas. -->
<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import MessageApi from 'dashboard/api/inbox/message';
import Button from 'dashboard/components-next/button/Button.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const { t } = useI18n();
const store = useStore();
const { isAdmin } = useAdmin();

const currentChat = useMapGetter('getSelectedChat');
const inbox = computed(() =>
  store.getters['inboxes/getInbox'](currentChat.value?.inbox_id)
);
const isBandejaDePruebas = computed(
  () => inbox.value?.channel_type === INBOX_TYPES.API
);
const showBox = computed(() => isAdmin.value && isBandejaDePruebas.value);

const mensaje = ref('');
const isSending = ref(false);

const enviar = async () => {
  if (!mensaje.value.trim()) return;

  isSending.value = true;
  try {
    await MessageApi.create({
      conversationId: currentChat.value.id,
      message: mensaje.value,
      message_type: 'incoming',
    });
    mensaje.value = '';
  } catch (error) {
    useAlert(
      error?.response?.data?.error ||
        t('CONVERSATION.CARTERA_PRUEBA.ENVIAR_ERROR')
    );
  } finally {
    isSending.value = false;
  }
};
</script>

<template>
  <div
    v-if="showBox"
    class="flex flex-col gap-2 p-3 border-t border-n-amber-6 bg-n-amber-3"
  >
    <p class="text-xs font-medium text-n-amber-11 mb-0">
      {{ t('CONVERSATION.CARTERA_PRUEBA.TITLE') }}
    </p>
    <div class="flex items-end gap-2">
      <TextArea
        v-model="mensaje"
        class="flex-1"
        :placeholder="t('CONVERSATION.CARTERA_PRUEBA.PLACEHOLDER')"
        rows="1"
        auto-height
        @keydown.enter.exact.prevent="enviar"
      />
      <Button
        icon="i-lucide-send"
        size="sm"
        :is-loading="isSending"
        :disabled="!mensaje.trim()"
        :label="t('CONVERSATION.CARTERA_PRUEBA.ENVIAR')"
        @click="enviar"
      />
    </div>
  </div>
</template>
