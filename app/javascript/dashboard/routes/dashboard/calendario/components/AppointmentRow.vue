<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  statusSelectOptions,
  statusRowBackgroundClass,
  RESCHEDULE_ACTION,
  ACTION_BUTTON_VARIANT,
  ACTION_BUTTON_CLASS,
} from '../helpers/appointmentStatusActions';
import { formatInstantTimeEs } from '../helpers/calendarioDateTime';
import { documentTypeAbbreviation } from '../helpers/documentTypeAbbreviation';

const props = defineProps({
  appointment: { type: Object, required: true },
  accountId: { type: [String, Number], required: true },
  updating: { type: Boolean, default: false },
});
const emit = defineEmits([
  'open-detail',
  'open-conversation',
  'set-status',
  'reschedule',
  'quick-book-after',
]);

const { t } = useI18n();

const statusOptions = computed(() => statusSelectOptions(t));

const contactUrl = computed(() =>
  frontendURL(
    `accounts/${props.accountId}/contacts/${props.appointment.contact_id}`
  )
);

const documentLabel = computed(() => {
  if (!props.appointment.contact_identifier) return '';
  return `${documentTypeAbbreviation(props.appointment.contact_document_type)} ${props.appointment.contact_identifier}`;
});

// Un solo numero visible (ahorra ancho, pedido explicito) -- si hay
// secundario, el tooltip al pasar el mouse muestra ambos.
const phoneTooltip = computed(() => {
  if (!props.appointment.contact_secondary_phone_number) return null;
  return `${props.appointment.contact_phone_number} / ${props.appointment.contact_secondary_phone_number}`;
});

// Reagendar una cita ya atendida no tiene sentido -- pedido explicito del
// usuario, aplica a ambas tablas (Agenda de hoy y Agendas) porque comparten
// este mismo componente de fila.
const canReschedule = computed(() => props.appointment.status !== 'attended');
</script>

<template>
  <div
    class="grid grid-cols-[2.75rem_minmax(0,1.4fr)_5.5rem_5rem_minmax(0,1fr)_minmax(0,0.8fr)_1.25rem_auto_auto_auto] items-center gap-x-2 py-1 px-1 cursor-pointer rounded-lg ring-1 ring-inset ring-transparent hover:ring-n-slate-6"
    :class="statusRowBackgroundClass(appointment.status)"
    @click="emit('open-detail', appointment)"
  >
    <span class="text-xs text-n-slate-10 tabular-nums">
      {{ formatInstantTimeEs(appointment.starts_at) }}
    </span>

    <router-link
      :to="contactUrl"
      class="text-xs font-medium text-n-slate-12 hover:underline truncate"
      @click.stop
    >
      {{ appointment.contact_name }}
    </router-link>

    <span class="text-xs text-n-slate-12 truncate">
      {{ documentLabel }}
    </span>

    <a
      v-if="appointment.contact_phone_number"
      v-tooltip.top="phoneTooltip"
      :href="`tel:${appointment.contact_phone_number}`"
      class="text-xs text-n-slate-12 hover:text-n-teal-9 hover:underline truncate"
      @click.stop
    >
      {{ appointment.contact_phone_number }}
    </a>
    <span v-else />

    <span class="text-xs text-n-slate-10 truncate">
      {{ appointment.service_name }}
    </span>

    <span class="text-xs text-n-slate-10 truncate">
      {{ appointment.payer_name }}
    </span>

    <button
      v-if="appointment.conversation_id"
      type="button"
      class="i-lucide-message-circle size-3.5 text-n-slate-10 hover:text-n-blue-text shrink-0"
      @click.stop="emit('open-conversation', appointment)"
    />
    <span v-else />

    <div @click.stop>
      <Select
        :model-value="appointment.status"
        :options="statusOptions"
        :disabled="updating"
        @update:model-value="status => emit('set-status', appointment, status)"
      />
    </div>

    <Button
      v-if="canReschedule"
      size="sm"
      :variant="ACTION_BUTTON_VARIANT"
      :class="ACTION_BUTTON_CLASS"
      :color="RESCHEDULE_ACTION.color"
      :icon="RESCHEDULE_ACTION.icon"
      :label="t(RESCHEDULE_ACTION.labelKey)"
      @click.stop="emit('reschedule', appointment)"
    />
    <span v-else />

    <Button
      v-tooltip.top="t('CALENDARIO.APPOINTMENTS.QUICK_BOOK_AFTER_TOOLTIP')"
      size="sm"
      faded
      slate
      icon="i-lucide-calendar-plus"
      @click.stop="emit('quick-book-after', appointment)"
    />
  </div>
</template>
