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
import ProfessionalFormModal from '../components/ProfessionalFormModal.vue';
import ProfessionalAvailabilityModal from '../components/ProfessionalAvailabilityModal.vue';

const { t } = useI18n();
const store = useStore();

const showFormModal = ref(false);
const showDeletePopup = ref(false);
const showAvailabilityModal = ref(false);
const selectedProfessional = ref(null);
const deletingId = ref(null);

const professionals = useMapGetter('calendarioProfessionals/getProfessionals');
const uiFlags = useMapGetter('calendarioProfessionals/getUIFlags');
const services = useMapGetter('calendarioServices/getServices');

const serviceNames = professional =>
  services.value
    .filter(service => service.professional_ids?.includes(professional.id))
    .map(service => service.name)
    .join(', ');

const openCreateModal = () => {
  selectedProfessional.value = null;
  showFormModal.value = true;
};
const openEditModal = professional => {
  selectedProfessional.value = professional;
  showFormModal.value = true;
};
const closeFormModal = () => {
  showFormModal.value = false;
};

const openAvailabilityModal = professional => {
  selectedProfessional.value = professional;
  showAvailabilityModal.value = true;
};
const closeAvailabilityModal = () => {
  showAvailabilityModal.value = false;
};

const openDeletePopup = professional => {
  selectedProfessional.value = professional;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};
const confirmDeletion = async () => {
  deletingId.value = selectedProfessional.value.id;
  closeDeletePopup();
  try {
    await store.dispatch(
      'calendarioProfessionals/delete',
      selectedProfessional.value.id
    );
    useAlert(t('CALENDARIO.PROFESSIONALS.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('CALENDARIO.PROFESSIONALS.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};

const tableHeaders = computed(() => [
  t('CALENDARIO.PROFESSIONALS.TABLE.NAME'),
  t('CALENDARIO.PROFESSIONALS.TABLE.SPECIALTY'),
  t('CALENDARIO.PROFESSIONALS.TABLE.SERVICES'),
  t('CALENDARIO.PROFESSIONALS.TABLE.STATUS'),
  t('CALENDARIO.PROFESSIONALS.TABLE.ACTIONS'),
]);

onMounted(async () => {
  try {
    await Promise.all([
      store.dispatch('calendarioProfessionals/get'),
      store.dispatch('calendarioServices/get'),
      store.dispatch('calendarioSpecialties/get'),
    ]);
  } catch (error) {
    useAlert(t('CALENDARIO.PROFESSIONALS.FETCH_ERROR'));
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
        {{ t('CALENDARIO.PROFESSIONALS.DESCRIPTION') }}
      </p>
      <Button
        :label="t('CALENDARIO.PROFESSIONALS.ADD_BUTTON')"
        size="sm"
        @click="openCreateModal"
      />
    </div>

    <BaseTable
      :headers="tableHeaders"
      :items="professionals"
      :no-data-message="t('CALENDARIO.PROFESSIONALS.EMPTY')"
    >
      <template #row="{ items }">
        <BaseTableRow
          v-for="professional in items"
          :key="professional.id"
          :item="professional"
        >
          <template #default>
            <BaseTableCell>{{ professional.name }}</BaseTableCell>
            <BaseTableCell>
              {{ professional.specialty_name || '—' }}
            </BaseTableCell>
            <BaseTableCell>
              {{ serviceNames(professional) || '—' }}
            </BaseTableCell>
            <BaseTableCell>
              {{
                professional.active
                  ? t('CALENDARIO.PROFESSIONALS.STATUS.ACTIVE')
                  : t('CALENDARIO.PROFESSIONALS.STATUS.INACTIVE')
              }}
            </BaseTableCell>
            <BaseTableCell align="end">
              <div class="flex gap-2 justify-end">
                <Button
                  v-tooltip.top="
                    t('CALENDARIO.PROFESSIONALS.AVAILABILITY.BUTTON')
                  "
                  icon="i-lucide-clock"
                  slate
                  sm
                  @click="openAvailabilityModal(professional)"
                />
                <Button
                  icon="i-woot-edit-pen"
                  slate
                  sm
                  @click="openEditModal(professional)"
                />
                <Button
                  icon="i-woot-bin"
                  slate
                  sm
                  :is-loading="deletingId === professional.id"
                  @click="openDeletePopup(professional)"
                />
              </div>
            </BaseTableCell>
          </template>
        </BaseTableRow>
      </template>
    </BaseTable>

    <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
      <ProfessionalFormModal
        :professional="selectedProfessional"
        @close="closeFormModal"
      />
    </woot-modal>

    <woot-modal
      v-model:show="showAvailabilityModal"
      :on-close="closeAvailabilityModal"
    >
      <ProfessionalAvailabilityModal
        v-if="selectedProfessional"
        :professional="selectedProfessional"
        @close="closeAvailabilityModal"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('CALENDARIO.PROFESSIONALS.DELETE_CONFIRM.TITLE')"
      :message="t('CALENDARIO.PROFESSIONALS.DELETE_CONFIRM.MESSAGE')"
      :confirm-text="t('CALENDARIO.PROFESSIONALS.DELETE_CONFIRM.CONFIRM')"
      :reject-text="t('CALENDARIO.PROFESSIONALS.DELETE_CONFIRM.CANCEL')"
    />
  </div>
</template>
