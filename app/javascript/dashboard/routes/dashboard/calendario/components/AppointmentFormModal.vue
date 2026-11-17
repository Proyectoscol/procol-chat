<script setup>
import { useI18n } from 'vue-i18n';
import AppointmentFormContent from './AppointmentFormContent.vue';

defineProps({
  presetContact: { type: Object, default: null },
  presetConversationId: { type: [Number, String], default: null },
  presetStartsAt: { type: Date, default: null },
  presetServiceId: { type: [Number, String], default: null },
  presetProfessionalId: { type: [Number, String], default: null },
});
defineEmits(['close', 'created']);

const { t } = useI18n();
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="t('CALENDARIO.APPOINTMENTS.FORM.CREATE_TITLE')"
    />
    <div class="px-4 pb-4">
      <AppointmentFormContent
        :preset-contact="presetContact"
        :preset-conversation-id="presetConversationId"
        :preset-starts-at="presetStartsAt"
        :preset-service-id="presetServiceId"
        :preset-professional-id="presetProfessionalId"
        @close="$emit('close')"
        @created="$emit('created', $event)"
      />
    </div>
  </div>
</template>
