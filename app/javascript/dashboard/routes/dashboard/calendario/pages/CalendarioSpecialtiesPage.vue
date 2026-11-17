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
import SpecialtyFormModal from '../components/SpecialtyFormModal.vue';

const { t } = useI18n();
const store = useStore();

const showFormModal = ref(false);
const showDeletePopup = ref(false);
const selectedSpecialty = ref(null);
const deletingId = ref(null);

const specialties = useMapGetter('calendarioSpecialties/getSpecialties');
const uiFlags = useMapGetter('calendarioSpecialties/getUIFlags');

const sortedSpecialties = computed(() =>
  [...specialties.value].sort((a, b) => a.name.localeCompare(b.name, 'es'))
);

const openCreateModal = () => {
  selectedSpecialty.value = null;
  showFormModal.value = true;
};
const openEditModal = specialty => {
  selectedSpecialty.value = specialty;
  showFormModal.value = true;
};
const closeFormModal = () => {
  showFormModal.value = false;
};

const openDeletePopup = specialty => {
  selectedSpecialty.value = specialty;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};
const confirmDeletion = async () => {
  deletingId.value = selectedSpecialty.value.id;
  closeDeletePopup();
  try {
    await store.dispatch(
      'calendarioSpecialties/delete',
      selectedSpecialty.value.id
    );
    useAlert(t('CALENDARIO.SPECIALTIES.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('CALENDARIO.SPECIALTIES.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};

const tableHeaders = computed(() => [
  t('CALENDARIO.SPECIALTIES.TABLE.NAME'),
  t('CALENDARIO.SPECIALTIES.TABLE.STATUS'),
  t('CALENDARIO.SPECIALTIES.TABLE.ACTIONS'),
]);

onMounted(async () => {
  try {
    await store.dispatch('calendarioSpecialties/get');
  } catch (error) {
    useAlert(t('CALENDARIO.SPECIALTIES.FETCH_ERROR'));
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
        {{ t('CALENDARIO.SPECIALTIES.DESCRIPTION') }}
      </p>
      <Button
        :label="t('CALENDARIO.SPECIALTIES.ADD_BUTTON')"
        size="sm"
        @click="openCreateModal"
      />
    </div>

    <BaseTable
      :headers="tableHeaders"
      :items="sortedSpecialties"
      :no-data-message="t('CALENDARIO.SPECIALTIES.EMPTY')"
    >
      <template #row="{ items }">
        <BaseTableRow
          v-for="specialty in items"
          :key="specialty.id"
          :item="specialty"
        >
          <template #default>
            <BaseTableCell>{{ specialty.name }}</BaseTableCell>
            <BaseTableCell>
              {{
                specialty.active
                  ? t('CALENDARIO.SPECIALTIES.STATUS.ACTIVE')
                  : t('CALENDARIO.SPECIALTIES.STATUS.INACTIVE')
              }}
            </BaseTableCell>
            <BaseTableCell align="end">
              <div class="flex gap-2 justify-end">
                <Button
                  icon="i-woot-edit-pen"
                  slate
                  sm
                  @click="openEditModal(specialty)"
                />
                <Button
                  icon="i-woot-bin"
                  slate
                  sm
                  :is-loading="deletingId === specialty.id"
                  @click="openDeletePopup(specialty)"
                />
              </div>
            </BaseTableCell>
          </template>
        </BaseTableRow>
      </template>
    </BaseTable>

    <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
      <SpecialtyFormModal
        :specialty="selectedSpecialty"
        @close="closeFormModal"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('CALENDARIO.SPECIALTIES.DELETE_CONFIRM.TITLE')"
      :message="t('CALENDARIO.SPECIALTIES.DELETE_CONFIRM.MESSAGE')"
      :confirm-text="t('CALENDARIO.SPECIALTIES.DELETE_CONFIRM.CONFIRM')"
      :reject-text="t('CALENDARIO.SPECIALTIES.DELETE_CONFIRM.CANCEL')"
    />
  </div>
</template>
