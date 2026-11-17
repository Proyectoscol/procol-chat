<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import ServiceFormModal from '../components/ServiceFormModal.vue';

const { t } = useI18n();
const store = useStore();

const showFormModal = ref(false);
const showDeletePopup = ref(false);
const selectedService = ref(null);
const deletingId = ref(null);

const services = useMapGetter('calendarioServices/getServices');
const uiFlags = useMapGetter('calendarioServices/getUIFlags');
const professionals = useMapGetter('calendarioProfessionals/getProfessionals');
const accountId = useMapGetter('getCurrentAccountId');

const professionalNames = service =>
  professionals.value
    .filter(professional => service.professional_ids?.includes(professional.id))
    .map(professional => professional.name)
    .join(', ');

const openCreateModal = () => {
  selectedService.value = null;
  showFormModal.value = true;
};
const openEditModal = service => {
  selectedService.value = service;
  showFormModal.value = true;
};
const closeFormModal = () => {
  showFormModal.value = false;
};

const openDeletePopup = service => {
  selectedService.value = service;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};
const confirmDeletion = async () => {
  deletingId.value = selectedService.value.id;
  closeDeletePopup();
  try {
    await store.dispatch('calendarioServices/delete', selectedService.value.id);
    useAlert(t('CALENDARIO.SERVICES.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('CALENDARIO.SERVICES.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};

const tableHeaders = computed(() => [
  t('CALENDARIO.SERVICES.TABLE.NAME'),
  t('CALENDARIO.SERVICES.TABLE.DURATION'),
  t('CALENDARIO.SERVICES.TABLE.KIND'),
  t('CALENDARIO.SERVICES.TABLE.PRICE'),
  t('CALENDARIO.SERVICES.TABLE.PROFESSIONALS'),
  t('CALENDARIO.SERVICES.TABLE.STATUS'),
  t('CALENDARIO.SERVICES.TABLE.ACTIONS'),
]);

const kindLabel = kind =>
  t(`CALENDARIO.SERVICES.TABLE.KIND_VALUES.${kind?.toUpperCase()}`);
const formatPrice = price =>
  price != null
    ? price.toLocaleString('es-CO', {
        style: 'currency',
        currency: 'COP',
        maximumFractionDigits: 0,
      })
    : '—';

onMounted(async () => {
  try {
    await Promise.all([
      store.dispatch('calendarioServices/get'),
      store.dispatch('calendarioProfessionals/get'),
    ]);
  } catch (error) {
    useAlert(t('CALENDARIO.SERVICES.FETCH_ERROR'));
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
        {{ t('CALENDARIO.SERVICES.DESCRIPTION') }}
      </p>
      <div class="flex items-center gap-2">
        <router-link
          :to="frontendURL(`accounts/${accountId}/calendario/payers`)"
          class="text-sm text-n-blue-text hover:underline"
        >
          {{ t('CALENDARIO.SERVICES.MANAGE_PAYERS_LINK') }}
        </router-link>
        <Button
          :label="t('CALENDARIO.SERVICES.ADD_BUTTON')"
          size="sm"
          @click="openCreateModal"
        />
      </div>
    </div>

    <BaseTable
      :headers="tableHeaders"
      :items="services"
      :no-data-message="t('CALENDARIO.SERVICES.EMPTY')"
    >
      <template #row="{ items }">
        <BaseTableRow
          v-for="service in items"
          :key="service.id"
          :item="service"
        >
          <template #default>
            <BaseTableCell>
              <div class="flex items-center gap-2">
                <span
                  class="size-3 rounded-full"
                  :style="{ backgroundColor: service.color }"
                />
                {{ service.name }}
              </div>
            </BaseTableCell>
            <BaseTableCell>
              {{
                t('CALENDARIO.SERVICES.TABLE.DURATION_MINUTES', {
                  count: service.duration_minutes,
                })
              }}
            </BaseTableCell>
            <BaseTableCell>{{ kindLabel(service.kind) }}</BaseTableCell>
            <BaseTableCell>{{ formatPrice(service.base_price) }}</BaseTableCell>
            <BaseTableCell>
              {{ professionalNames(service) || '—' }}
            </BaseTableCell>
            <BaseTableCell>
              {{
                service.active
                  ? t('CALENDARIO.SERVICES.STATUS.ACTIVE')
                  : t('CALENDARIO.SERVICES.STATUS.INACTIVE')
              }}
            </BaseTableCell>
            <BaseTableCell align="end">
              <div class="flex gap-2 justify-end">
                <Button
                  icon="i-woot-edit-pen"
                  slate
                  sm
                  @click="openEditModal(service)"
                />
                <Button
                  icon="i-woot-bin"
                  slate
                  sm
                  :is-loading="deletingId === service.id"
                  @click="openDeletePopup(service)"
                />
              </div>
            </BaseTableCell>
          </template>
        </BaseTableRow>
      </template>
    </BaseTable>

    <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
      <ServiceFormModal :service="selectedService" @close="closeFormModal" />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('CALENDARIO.SERVICES.DELETE_CONFIRM.TITLE')"
      :message="t('CALENDARIO.SERVICES.DELETE_CONFIRM.MESSAGE')"
      :confirm-text="t('CALENDARIO.SERVICES.DELETE_CONFIRM.CONFIRM')"
      :reject-text="t('CALENDARIO.SERVICES.DELETE_CONFIRM.CANCEL')"
    />
  </div>
</template>
