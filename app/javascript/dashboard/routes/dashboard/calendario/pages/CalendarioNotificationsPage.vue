<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { isWhatsAppCapableInbox } from 'dashboard/helper/inbox';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import AppointmentEventTriggerFormModal from '../components/AppointmentEventTriggerFormModal.vue';

const { t } = useI18n();
const store = useStore();

const showFormModal = ref(false);
const showDeletePopup = ref(false);
const selectedTrigger = ref(null);
const deletingId = ref(null);

const triggers = useMapGetter('calendarioAppointmentEventTriggers/getTriggers');
const uiFlags = useMapGetter('calendarioAppointmentEventTriggers/getUIFlags');
const allInboxes = useMapGetter('inboxes/getInboxes');
const whatsappInboxes = computed(() =>
  allInboxes.value.filter(isWhatsAppCapableInbox)
);
const allServices = useMapGetter('calendarioServices/getServices');

const hasNoWhatsappInbox = computed(() => whatsappInboxes.value.length === 0);

// Filtro por servicio en vez de carpetas -- pedido explicito del usuario
// 2026-11-25: una notificacion puede aplicar a "todos los servicios"
// (ej. el recordatorio de 1h), asi que agruparlas en carpetas por servicio
// dejaria sin hogar claro a esas. Filtrar en cambio: "todos" siempre
// aparece sin importar que servicio este seleccionado.
const serviceFilter = ref('');
const serviceFilterOptions = computed(() => [
  { value: '', label: t('CALENDARIO.TRIGGERS.ALL_SERVICES_FILTER') },
  ...allServices.value.map(service => ({
    value: service.id,
    label: service.name,
  })),
]);

const sortedTriggers = computed(() => {
  const filtered = serviceFilter.value
    ? triggers.value.filter(
        trigger =>
          !trigger.services?.length ||
          trigger.services.some(service => service.id === serviceFilter.value)
      )
    : triggers.value;
  return [...filtered].sort((a, b) => a.id - b.id);
});

const kindLabel = trigger => {
  if (trigger.trigger_kind === 'on_status_change') {
    const status = t(
      `CALENDARIO.APPOINTMENTS.STATUS.${trigger.target_status?.toUpperCase()}`
    );
    if (trigger.offset_minutes) {
      return t('CALENDARIO.TRIGGERS.KIND_VALUES.ON_STATUS_CHANGE_DELAYED', {
        status,
        minutes: trigger.offset_minutes,
      });
    }
    return t('CALENDARIO.TRIGGERS.KIND_VALUES.ON_STATUS_CHANGE', { status });
  }
  if (trigger.trigger_kind === 'before_start') {
    return t('CALENDARIO.TRIGGERS.KIND_VALUES.BEFORE_START', {
      minutes: trigger.offset_minutes,
    });
  }
  if (trigger.trigger_kind === 'on_reschedule') {
    return t('CALENDARIO.TRIGGERS.KIND_VALUES.ON_RESCHEDULE');
  }
  return t('CALENDARIO.TRIGGERS.KIND_VALUES.ON_CREATE');
};

const servicesLabel = trigger => {
  if (!trigger.services?.length) return t('CALENDARIO.TRIGGERS.ALL_SERVICES');
  return trigger.services.map(service => service.name).join(', ');
};

const payerKindsLabel = trigger => {
  if (!trigger.payer_kinds?.length) {
    return t('CALENDARIO.TRIGGERS.ALL_PAYER_KINDS');
  }
  return trigger.payer_kinds
    .map(kind => t(`CALENDARIO.PAYERS.KIND_VALUES.${kind.toUpperCase()}`))
    .join(', ');
};

const openCreateModal = () => {
  selectedTrigger.value = null;
  showFormModal.value = true;
};
const openEditModal = trigger => {
  selectedTrigger.value = trigger;
  showFormModal.value = true;
};
const closeFormModal = () => {
  showFormModal.value = false;
};

const openDeletePopup = trigger => {
  selectedTrigger.value = trigger;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};
const confirmDeletion = async () => {
  deletingId.value = selectedTrigger.value.id;
  closeDeletePopup();
  try {
    await store.dispatch(
      'calendarioAppointmentEventTriggers/delete',
      selectedTrigger.value.id
    );
    useAlert(t('CALENDARIO.TRIGGERS.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('CALENDARIO.TRIGGERS.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};

const tableHeaders = computed(() => [
  t('CALENDARIO.TRIGGERS.TABLE.KIND'),
  t('CALENDARIO.TRIGGERS.TABLE.SERVICE'),
  t('CALENDARIO.TRIGGERS.TABLE.PAYER_KIND'),
  t('CALENDARIO.TRIGGERS.TABLE.INBOX'),
  t('CALENDARIO.TRIGGERS.TABLE.TEMPLATE'),
  t('CALENDARIO.TRIGGERS.TABLE.STATUS'),
  t('CALENDARIO.TRIGGERS.TABLE.ACTIONS'),
]);

onMounted(async () => {
  store.dispatch('inboxes/get');
  store.dispatch('calendarioServices/get');
  try {
    await store.dispatch('calendarioAppointmentEventTriggers/get');
  } catch (error) {
    useAlert(t('CALENDARIO.TRIGGERS.FETCH_ERROR'));
  }
});
</script>

<template>
  <div v-if="uiFlags.isFetching" class="flex items-center justify-center py-8">
    <Spinner />
  </div>
  <div v-else class="flex flex-col gap-4">
    <div class="flex items-center justify-between">
      <p class="text-sm text-n-slate-11">
        {{ t('CALENDARIO.TRIGGERS.DESCRIPTION') }}
      </p>
      <Button
        :label="t('CALENDARIO.TRIGGERS.ADD_BUTTON')"
        size="sm"
        :disabled="hasNoWhatsappInbox"
        @click="openCreateModal"
      />
    </div>

    <p v-if="hasNoWhatsappInbox" class="text-sm text-n-amber-11">
      {{ t('CALENDARIO.TRIGGERS.NO_WHATSAPP_INBOX_WARNING') }}
    </p>

    <div class="flex items-center gap-2 max-w-xs">
      <label class="text-sm text-n-slate-11 whitespace-nowrap">
        {{ t('CALENDARIO.TRIGGERS.SERVICE_FILTER_LABEL') }}
      </label>
      <Select v-model="serviceFilter" :options="serviceFilterOptions" />
    </div>

    <BaseTable
      :headers="tableHeaders"
      :items="sortedTriggers"
      :no-data-message="t('CALENDARIO.TRIGGERS.EMPTY')"
    >
      <template #row="{ items }">
        <BaseTableRow
          v-for="trigger in items"
          :key="trigger.id"
          :item="trigger"
        >
          <template #default>
            <BaseTableCell>{{ kindLabel(trigger) }}</BaseTableCell>
            <BaseTableCell>{{ servicesLabel(trigger) }}</BaseTableCell>
            <BaseTableCell>{{ payerKindsLabel(trigger) }}</BaseTableCell>
            <BaseTableCell>{{ trigger.inbox_name }}</BaseTableCell>
            <BaseTableCell>{{ trigger.template_params?.name }}</BaseTableCell>
            <BaseTableCell>
              <div class="flex items-center gap-1.5">
                <span>
                  {{
                    trigger.active
                      ? t('CALENDARIO.TRIGGERS.STATUS.ACTIVE')
                      : t('CALENDARIO.TRIGGERS.STATUS.INACTIVE')
                  }}
                </span>
                <!-- Burbuja visible de un vistazo -- pedido explicito del
                usuario antes de produccion: saber cuales disparadores
                mandan nota privada (prueba) vs mensaje real. -->
                <span
                  v-if="trigger.test_mode"
                  class="text-[10px] font-medium rounded px-1.5 py-0.5 bg-n-amber-3 text-n-amber-11"
                >
                  {{ t('CALENDARIO.TRIGGERS.TEST_MODE_BADGE') }}
                </span>
              </div>
            </BaseTableCell>
            <BaseTableCell align="end">
              <div class="flex gap-2 justify-end">
                <Button
                  icon="i-woot-edit-pen"
                  slate
                  sm
                  @click="openEditModal(trigger)"
                />
                <Button
                  icon="i-woot-bin"
                  slate
                  sm
                  :is-loading="deletingId === trigger.id"
                  @click="openDeletePopup(trigger)"
                />
              </div>
            </BaseTableCell>
          </template>
        </BaseTableRow>
      </template>
    </BaseTable>

    <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
      <AppointmentEventTriggerFormModal
        :trigger="selectedTrigger"
        @close="closeFormModal"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('CALENDARIO.TRIGGERS.DELETE_CONFIRM.TITLE')"
      :message="t('CALENDARIO.TRIGGERS.DELETE_CONFIRM.MESSAGE')"
      :confirm-text="t('CALENDARIO.TRIGGERS.DELETE_CONFIRM.CONFIRM')"
      :reject-text="t('CALENDARIO.TRIGGERS.DELETE_CONFIRM.CANCEL')"
    />
  </div>
</template>
