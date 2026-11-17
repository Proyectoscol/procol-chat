<script setup>
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { useAppointmentDetail } from '../composables/useAppointmentDetail';
import {
  RESCHEDULE_ACTION,
  ACTION_BUTTON_VARIANT,
  ACTION_BUTTON_CLASS,
  statusRowBackgroundClass,
} from '../helpers/appointmentStatusActions';

const props = defineProps({
  appointmentId: { type: [Number, String], required: true },
  // Dentro de la conversacion ya estamos viendo esa conversacion -- el boton
  // "abrir conversacion" no tiene sentido ahi (ver AppointmentDetailDrawer).
  showOpenConversation: { type: Boolean, default: true },
});
const emit = defineEmits(['close', 'reschedule', 'cancel', 'changed']);

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const {
  isFetching,
  isUpdatingStatus,
  appointment,
  statusOptions,
  statusLabel,
  formatDateTime,
  rescheduleCountLabel,
  historyLabel,
  setStatus,
} = useAppointmentDetail(props.appointmentId, {
  onChanged: () => emit('changed'),
});

const openConversation = () => {
  if (!appointment.value?.conversation_id) return;
  router.push(
    frontendURL(
      conversationUrl({
        accountId: accountId.value,
        id: appointment.value.conversation_id,
      })
    )
  );
  emit('close');
};

const formatPrice = price =>
  price != null
    ? price.toLocaleString('es-CO', {
        style: 'currency',
        currency: 'COP',
        maximumFractionDigits: 0,
      })
    : '—';

const requestReschedule = () => {
  emit('reschedule', appointment.value);
  emit('close');
};

// Cancelar necesita un motivo obligatorio (ver CancelAppointmentModal/Drawer) -- no
// se puede resolver aqui mismo porque ese modal tiene que montarse por
// encima de este (el mismo patron que reagendar). Por eso el selector de
// estado no se liga directo a setStatus: intercepta "cancelled" para abrir
// ese flujo en vez de aplicar el cambio de una.
const onStatusSelected = status => {
  if (status === 'cancelled') {
    emit('cancel', appointment.value);
    emit('close');
    return;
  }
  setStatus(status);
};
</script>

<template>
  <div v-if="isFetching" class="flex items-center justify-center py-10">
    <Spinner />
  </div>
  <div
    v-else-if="appointment"
    class="flex flex-col gap-4 rounded-xl p-3"
    :class="statusRowBackgroundClass(appointment.status)"
  >
    <div class="flex flex-col gap-1">
      <span class="text-xs text-n-slate-10">{{
        t('CALENDARIO.APPOINTMENTS.DETAIL.CONTACT')
      }}</span>
      <div class="flex items-center justify-between gap-2">
        <span class="text-sm font-medium text-n-slate-12">{{
          appointment.contact_name
        }}</span>
        <Button
          v-if="showOpenConversation && appointment.conversation_id"
          size="sm"
          slate
          icon="i-lucide-message-circle"
          :label="t('CALENDARIO.APPOINTMENTS.DETAIL.OPEN_CONVERSATION')"
          @click="openConversation"
        />
      </div>
      <span
        v-if="appointment.contact_phone_number"
        class="text-xs text-n-slate-11"
      >
        {{ appointment.contact_phone_number }}
      </span>
      <span v-if="appointment.contact_email" class="text-xs text-n-slate-11">
        {{ appointment.contact_email }}
      </span>
    </div>

    <div class="grid grid-cols-2 gap-3">
      <div class="flex flex-col gap-0.5">
        <span class="text-xs text-n-slate-10">{{
          t('CALENDARIO.APPOINTMENTS.DETAIL.SERVICE')
        }}</span>
        <span class="text-sm text-n-slate-12">{{
          appointment.service_name
        }}</span>
      </div>
      <div class="flex flex-col gap-0.5">
        <span class="text-xs text-n-slate-10">{{
          t('CALENDARIO.APPOINTMENTS.DETAIL.PROFESSIONAL')
        }}</span>
        <span class="text-sm text-n-slate-12">{{
          appointment.professional_name
        }}</span>
      </div>
      <div class="flex flex-col gap-0.5">
        <span class="text-xs text-n-slate-10">{{
          t('CALENDARIO.APPOINTMENTS.DETAIL.WHEN')
        }}</span>
        <span class="text-sm text-n-slate-12">{{
          formatDateTime(appointment.starts_at)
        }}</span>
      </div>
      <div class="flex flex-col gap-0.5">
        <span class="text-xs text-n-slate-10">{{
          t('CALENDARIO.APPOINTMENTS.DETAIL.PAYER')
        }}</span>
        <span class="text-sm text-n-slate-12">{{
          appointment.payer_name || t('CALENDARIO.APPOINTMENTS.DETAIL.NO_PAYER')
        }}</span>
      </div>
      <div class="flex flex-col gap-0.5">
        <span class="text-xs text-n-slate-10">{{
          t('CALENDARIO.APPOINTMENTS.DETAIL.PRICE')
        }}</span>
        <span class="text-sm text-n-slate-12">{{
          formatPrice(appointment.price)
        }}</span>
      </div>
      <div class="flex flex-col gap-0.5">
        <span class="text-xs text-n-slate-10">{{
          t('CALENDARIO.APPOINTMENTS.DETAIL.STATUS')
        }}</span>
        <span class="text-sm text-n-slate-12">
          {{ statusLabel(appointment.status) }}
          <template v-if="appointment.reschedules_count > 0">
            · {{ rescheduleCountLabel(appointment.reschedules_count) }}
          </template>
        </span>
      </div>
      <!-- Para auditoria: cuando (y quien) registro la cita -- distinto de
      "Fecha y hora" (que es para CUANDO quedo agendada la atencion). Ante un
      reclamo ("yo nunca reserve esto") esto es lo primero que hay que ver. -->
      <div class="flex flex-col gap-0.5">
        <span class="text-xs text-n-slate-10">{{
          t('CALENDARIO.APPOINTMENTS.DETAIL.CREATED_AT')
        }}</span>
        <span class="text-sm text-n-slate-12">
          {{ formatDateTime(appointment.created_at) }}
          <template v-if="appointment.created_by_name">
            ·
            {{
              t('CALENDARIO.APPOINTMENTS.DETAIL.CREATED_BY', {
                name: appointment.created_by_name,
              })
            }}
          </template>
        </span>
      </div>
    </div>

    <div v-if="appointment.notes" class="flex flex-col gap-0.5">
      <span class="text-xs text-n-slate-10">{{
        t('CALENDARIO.APPOINTMENTS.DETAIL.NOTES')
      }}</span>
      <p class="text-sm text-n-slate-12 whitespace-pre-wrap">
        {{ appointment.notes }}
      </p>
    </div>

    <div class="flex flex-col gap-1">
      <span class="text-xs text-n-slate-10">{{
        t('CALENDARIO.APPOINTMENTS.DETAIL.ACTIONS_TITLE')
      }}</span>
      <div class="flex flex-wrap items-center gap-2">
        <Select
          :model-value="appointment.status"
          :options="statusOptions"
          :disabled="isUpdatingStatus"
          @update:model-value="onStatusSelected"
        />
        <Button
          size="sm"
          :variant="ACTION_BUTTON_VARIANT"
          :class="ACTION_BUTTON_CLASS"
          :color="RESCHEDULE_ACTION.color"
          :icon="RESCHEDULE_ACTION.icon"
          :label="t(RESCHEDULE_ACTION.labelKey)"
          @click="requestReschedule"
        />
      </div>
    </div>

    <div v-if="appointment.history?.length" class="flex flex-col gap-2">
      <span class="text-xs text-n-slate-10">{{
        t('CALENDARIO.APPOINTMENTS.DETAIL.HISTORY_TITLE')
      }}</span>
      <div class="flex flex-col gap-2 border border-n-weak rounded-lg p-3">
        <div
          v-for="entry in appointment.history"
          :key="entry.id"
          class="flex flex-col gap-0.5 text-xs border-l-2 border-n-weak pl-2 py-0.5"
        >
          <span class="text-n-slate-12">{{ historyLabel(entry) }}</span>
          <span class="text-n-slate-10">
            {{ formatDateTime(entry.created_at) }}
            <template v-if="entry.user_name"> · {{ entry.user_name }}</template>
          </span>
        </div>
      </div>
    </div>
  </div>
</template>
