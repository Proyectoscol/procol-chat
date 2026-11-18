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
import WelcomeBotFlowFormModal from '../components/WelcomeBotFlowFormModal.vue';

const { t } = useI18n();
const store = useStore();

const showFormModal = ref(false);
const showDeletePopup = ref(false);
const selectedFlow = ref(null);
const deletingId = ref(null);

const flows = useMapGetter('calendarioWelcomeBotFlows/getFlows');
const uiFlags = useMapGetter('calendarioWelcomeBotFlows/getUIFlags');

const matchLabel = flow =>
  flow.match_type === 'keyword'
    ? t('CALENDARIO.WELCOME_BOT.TABLE.KEYWORD_MATCH', {
        value: flow.match_value,
      })
    : t('CALENDARIO.WELCOME_BOT.TABLE.DEFAULT_MATCH');

const tableHeaders = computed(() => [
  t('CALENDARIO.WELCOME_BOT.TABLE.NAME'),
  t('CALENDARIO.WELCOME_BOT.TABLE.MATCH'),
  t('CALENDARIO.WELCOME_BOT.TABLE.PRIORITY'),
  t('CALENDARIO.WELCOME_BOT.TABLE.STEPS'),
  t('CALENDARIO.WELCOME_BOT.TABLE.INBOX'),
  t('CALENDARIO.WELCOME_BOT.TABLE.STATUS'),
  t('CALENDARIO.WELCOME_BOT.TABLE.ACTIONS'),
]);

const openCreateModal = () => {
  selectedFlow.value = null;
  showFormModal.value = true;
};
const openEditModal = flow => {
  selectedFlow.value = flow;
  showFormModal.value = true;
};
const closeFormModal = () => {
  showFormModal.value = false;
};

const openDeletePopup = flow => {
  selectedFlow.value = flow;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};
const confirmDeletion = async () => {
  deletingId.value = selectedFlow.value.id;
  closeDeletePopup();
  try {
    await store.dispatch(
      'calendarioWelcomeBotFlows/delete',
      selectedFlow.value.id
    );
    useAlert(t('CALENDARIO.WELCOME_BOT.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('CALENDARIO.WELCOME_BOT.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};

onMounted(async () => {
  store.dispatch('inboxes/get');
  try {
    await store.dispatch('calendarioWelcomeBotFlows/get');
  } catch (error) {
    useAlert(t('CALENDARIO.WELCOME_BOT.FETCH_ERROR'));
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
        {{ t('CALENDARIO.WELCOME_BOT.DESCRIPTION') }}
      </p>
      <Button
        :label="t('CALENDARIO.WELCOME_BOT.ADD_BUTTON')"
        size="sm"
        @click="openCreateModal"
      />
    </div>

    <BaseTable
      :headers="tableHeaders"
      :items="flows"
      :no-data-message="t('CALENDARIO.WELCOME_BOT.EMPTY')"
    >
      <template #row="{ items }">
        <BaseTableRow v-for="flow in items" :key="flow.id" :item="flow">
          <template #default>
            <BaseTableCell>{{ flow.name }}</BaseTableCell>
            <BaseTableCell>{{ matchLabel(flow) }}</BaseTableCell>
            <BaseTableCell>{{ flow.priority }}</BaseTableCell>
            <BaseTableCell>{{ flow.steps.length }}</BaseTableCell>
            <BaseTableCell>{{ flow.inbox_name }}</BaseTableCell>
            <BaseTableCell>
              {{
                flow.active
                  ? t('CALENDARIO.WELCOME_BOT.STATUS.ACTIVE')
                  : t('CALENDARIO.WELCOME_BOT.STATUS.INACTIVE')
              }}
            </BaseTableCell>
            <BaseTableCell align="end">
              <div class="flex gap-2 justify-end">
                <Button
                  icon="i-woot-edit-pen"
                  slate
                  sm
                  @click="openEditModal(flow)"
                />
                <Button
                  icon="i-woot-bin"
                  slate
                  sm
                  :is-loading="deletingId === flow.id"
                  @click="openDeletePopup(flow)"
                />
              </div>
            </BaseTableCell>
          </template>
        </BaseTableRow>
      </template>
    </BaseTable>

    <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
      <WelcomeBotFlowFormModal :flow="selectedFlow" @close="closeFormModal" />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('CALENDARIO.WELCOME_BOT.DELETE_CONFIRM.TITLE')"
      :message="t('CALENDARIO.WELCOME_BOT.DELETE_CONFIRM.MESSAGE')"
      :confirm-text="t('CALENDARIO.WELCOME_BOT.DELETE_CONFIRM.CONFIRM')"
      :reject-text="t('CALENDARIO.WELCOME_BOT.DELETE_CONFIRM.CANCEL')"
    />
  </div>
</template>
