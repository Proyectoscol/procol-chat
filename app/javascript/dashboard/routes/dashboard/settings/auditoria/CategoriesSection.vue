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
import CategoryFormModal from './CategoryFormModal.vue';

const { t } = useI18n();
const store = useStore();

const MAX_CATEGORIES = 10;

const showFormModal = ref(false);
const showDeletePopup = ref(false);
const selectedCategory = ref(null);
const deletingId = ref(null);

const categories = useMapGetter('auditoriaCategories/getCategories');
const uiFlags = useMapGetter('auditoriaCategories/getUIFlags');
const canAddCategory = computed(() => categories.value.length < MAX_CATEGORIES);

const titleById = computed(() =>
  Object.fromEntries(categories.value.map(c => [c.id, c.title]))
);
const parentTitle = category => titleById.value[category.parent_id];

// Una categoria con subcategorias es pura agrupacion -- su match_type
// propio quedo sin efecto (ver Auditoria::Category.leaf), mostrarlo
// confundiria.
const matchTypeLabel = category => {
  if (category.has_subcategories) {
    return t('AUDITORIA_CATEGORIES.MATCH_TYPE.GROUPING');
  }
  return category.match_type === 'keyword'
    ? t('AUDITORIA_CATEGORIES.MATCH_TYPE.KEYWORD')
    : t('AUDITORIA_CATEGORIES.MATCH_TYPE.AI');
};

const openCreateModal = () => {
  selectedCategory.value = null;
  showFormModal.value = true;
};
const openEditModal = category => {
  selectedCategory.value = category;
  showFormModal.value = true;
};
const closeFormModal = () => {
  showFormModal.value = false;
};

const openDeletePopup = category => {
  selectedCategory.value = category;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};
const confirmDeletion = async () => {
  deletingId.value = selectedCategory.value.id;
  closeDeletePopup();
  try {
    await store.dispatch(
      'auditoriaCategories/delete',
      selectedCategory.value.id
    );
    useAlert(t('AUDITORIA_CATEGORIES.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('AUDITORIA_CATEGORIES.DELETE_ERROR'));
  } finally {
    deletingId.value = null;
  }
};

const tableHeaders = computed(() => [
  t('AUDITORIA_CATEGORIES.TABLE.TITLE'),
  t('AUDITORIA_CATEGORIES.TABLE.TYPE'),
  t('AUDITORIA_CATEGORIES.TABLE.STATUS'),
  t('AUDITORIA_CATEGORIES.TABLE.ACTIONS'),
]);

onMounted(() => store.dispatch('auditoriaCategories/get'));
</script>

<template>
  <div v-if="uiFlags.isFetching" class="flex items-center justify-center py-8">
    <Spinner />
  </div>
  <div v-else class="flex flex-col gap-4">
    <div class="flex items-center justify-between">
      <p class="text-sm text-n-slate-11">
        {{ t('AUDITORIA_CATEGORIES.DESCRIPTION') }}
      </p>
      <Button
        :label="t('AUDITORIA_CATEGORIES.ADD_BUTTON')"
        size="sm"
        :disabled="!canAddCategory"
        @click="openCreateModal"
      />
    </div>

    <BaseTable
      :headers="tableHeaders"
      :items="categories"
      :no-data-message="t('AUDITORIA_CATEGORIES.EMPTY')"
    >
      <template #row="{ items }">
        <BaseTableRow
          v-for="category in items"
          :key="category.id"
          :item="category"
        >
          <template #default>
            <BaseTableCell>
              <div class="flex flex-col">
                <span class="text-body-main text-n-slate-12">{{
                  category.title
                }}</span>
                <span v-if="category.parent_id" class="text-xs text-n-slate-10">
                  {{
                    t('AUDITORIA_CATEGORIES.TABLE.PARENT_OF', {
                      parent: parentTitle(category),
                    })
                  }}
                </span>
              </div>
            </BaseTableCell>
            <BaseTableCell>
              {{ matchTypeLabel(category) }}
            </BaseTableCell>
            <BaseTableCell>
              {{
                category.is_active
                  ? t('AUDITORIA_CATEGORIES.STATUS.ACTIVE')
                  : t('AUDITORIA_CATEGORIES.STATUS.INACTIVE')
              }}
            </BaseTableCell>
            <BaseTableCell align="end">
              <div class="flex gap-2 justify-end">
                <Button
                  icon="i-woot-edit-pen"
                  slate
                  sm
                  @click="openEditModal(category)"
                />
                <Button
                  icon="i-woot-bin"
                  slate
                  sm
                  class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                  :is-loading="deletingId === category.id"
                  @click="openDeletePopup(category)"
                />
              </div>
            </BaseTableCell>
          </template>
        </BaseTableRow>
      </template>
    </BaseTable>

    <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
      <CategoryFormModal :category="selectedCategory" @close="closeFormModal" />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('AUDITORIA_CATEGORIES.DELETE_CONFIRM.TITLE')"
      :message="t('AUDITORIA_CATEGORIES.DELETE_CONFIRM.MESSAGE')"
      :confirm-text="t('AUDITORIA_CATEGORIES.DELETE_CONFIRM.YES')"
      :reject-text="t('AUDITORIA_CATEGORIES.DELETE_CONFIRM.NO')"
    />
  </div>
</template>
