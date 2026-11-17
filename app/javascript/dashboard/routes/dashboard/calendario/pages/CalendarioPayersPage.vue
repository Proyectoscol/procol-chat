<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';
import PayerFormModal from '../components/PayerFormModal.vue';

const { t } = useI18n();
const store = useStore();

const showFormModal = ref(false);
const showDeletePopup = ref(false);
const selectedPayer = ref(null);
const deletingId = ref(null);

const payers = useMapGetter('calendarioPayers/getPayers');
const uiFlags = useMapGetter('calendarioPayers/getUIFlags');

// Orden alfabetico -- antes el backend los devolvia agrupados por "kind",
// que no es como el personal busca una EPS por nombre.
const sortedPayers = computed(() =>
  [...payers.value].sort((a, b) => a.name.localeCompare(b.name, 'es'))
);

const openCreateModal = () => {
  selectedPayer.value = null;
  showFormModal.value = true;
};
const openEditModal = payer => {
  selectedPayer.value = payer;
  showFormModal.value = true;
};
const closeFormModal = () => {
  showFormModal.value = false;
};

const openDeletePopup = payer => {
  selectedPayer.value = payer;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};
const confirmDeletion = async () => {
  deletingId.value = selectedPayer.value.id;
  closeDeletePopup();
  try {
    await store.dispatch('calendarioPayers/delete', selectedPayer.value.id);
    useAlert(t('CALENDARIO.PAYERS.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('CALENDARIO.PAYERS.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};

const tableHeaders = computed(() => [
  t('CALENDARIO.PAYERS.TABLE.NAME'),
  t('CALENDARIO.PAYERS.TABLE.KIND'),
  t('CALENDARIO.PAYERS.TABLE.STATUS'),
  t('CALENDARIO.PAYERS.TABLE.ACTIONS'),
]);

const kindLabel = kind =>
  t(`CALENDARIO.PAYERS.KIND_VALUES.${kind?.toUpperCase()}`);

onMounted(async () => {
  try {
    await store.dispatch('calendarioPayers/get');
  } catch (error) {
    useAlert(t('CALENDARIO.PAYERS.FETCH_ERROR'));
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
        {{ t('CALENDARIO.PAYERS.DESCRIPTION') }}
      </p>
      <Button
        :label="t('CALENDARIO.PAYERS.ADD_BUTTON')"
        size="sm"
        @click="openCreateModal"
      />
    </div>

    <BaseTable
      :headers="tableHeaders"
      :items="sortedPayers"
      :no-data-message="t('CALENDARIO.PAYERS.EMPTY')"
    >
      <template #row="{ items }">
        <BaseTableRow v-for="payer in items" :key="payer.id" :item="payer">
          <template #default>
            <BaseTableCell>{{ payer.name }}</BaseTableCell>
            <BaseTableCell>{{ kindLabel(payer.kind) }}</BaseTableCell>
            <BaseTableCell>
              {{
                payer.active
                  ? t('CALENDARIO.PAYERS.STATUS.ACTIVE')
                  : t('CALENDARIO.PAYERS.STATUS.INACTIVE')
              }}
            </BaseTableCell>
            <BaseTableCell align="end">
              <div class="flex gap-2 justify-end">
                <Button
                  icon="i-woot-edit-pen"
                  slate
                  sm
                  @click="openEditModal(payer)"
                />
                <Button
                  icon="i-woot-bin"
                  slate
                  sm
                  :is-loading="deletingId === payer.id"
                  @click="openDeletePopup(payer)"
                />
              </div>
            </BaseTableCell>
          </template>
        </BaseTableRow>
      </template>
    </BaseTable>

    <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
      <PayerFormModal :payer="selectedPayer" @close="closeFormModal" />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('CALENDARIO.PAYERS.DELETE_CONFIRM.TITLE')"
      :message="t('CALENDARIO.PAYERS.DELETE_CONFIRM.MESSAGE')"
      :confirm-text="t('CALENDARIO.PAYERS.DELETE_CONFIRM.CONFIRM')"
      :reject-text="t('CALENDARIO.PAYERS.DELETE_CONFIRM.CANCEL')"
    />
  </div>
</template>
