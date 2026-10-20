<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  category: { type: Object, default: null }, // null => crear, objeto => editar
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const isEditMode = computed(() => !!props.category);

const title = ref('');
const matchType = ref('keyword');
const isActive = ref(true);
const searchTerms = ref('');
const instructions = ref('');
const isSaving = ref(false);

const matchTypeOptions = computed(() => [
  {
    value: 'keyword',
    label: t('AUDITORIA_CATEGORIES.FORM.MATCH_TYPE.KEYWORD'),
  },
  { value: 'ai', label: t('AUDITORIA_CATEGORIES.FORM.MATCH_TYPE.AI') },
]);

const setFormValues = () => {
  title.value = props.category?.title || '';
  matchType.value = props.category?.match_type || 'keyword';
  isActive.value = props.category ? props.category.is_active : true;
  searchTerms.value = props.category?.search_terms || '';
  instructions.value = props.category?.instructions || '';
};
watch(() => props.category, setFormValues, { immediate: true });

const isFormInvalid = computed(() => !title.value.trim());

const onClose = () => emit('close');

const submit = async () => {
  isSaving.value = true;
  const payload = {
    title: title.value,
    match_type: matchType.value,
    is_active: isActive.value,
    search_terms: matchType.value === 'keyword' ? searchTerms.value : '',
    instructions: matchType.value === 'ai' ? instructions.value : '',
  };
  try {
    if (isEditMode.value) {
      await store.dispatch('auditoriaCategories/update', {
        id: props.category.id,
        ...payload,
      });
      useAlert(t('AUDITORIA_CATEGORIES.FORM.EDIT_SUCCESS'));
    } else {
      await store.dispatch('auditoriaCategories/create', payload);
      useAlert(t('AUDITORIA_CATEGORIES.FORM.CREATE_SUCCESS'));
    }
    onClose();
  } catch (error) {
    useAlert(
      error?.response?.data?.errors?.[0] || t('AUDITORIA_CATEGORIES.FORM.ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="
        isEditMode
          ? t('AUDITORIA_CATEGORIES.FORM.EDIT_TITLE')
          : t('AUDITORIA_CATEGORIES.FORM.CREATE_TITLE')
      "
    />
    <form class="flex flex-col gap-4 px-4 pb-4" @submit.prevent="submit">
      <Input
        v-model="title"
        :label="t('AUDITORIA_CATEGORIES.FORM.TITLE_LABEL')"
        :placeholder="t('AUDITORIA_CATEGORIES.FORM.TITLE_PLACEHOLDER')"
      />
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('AUDITORIA_CATEGORIES.FORM.MATCH_TYPE_LABEL') }}
        </label>
        <Select v-model="matchType" :options="matchTypeOptions" />
      </div>
      <TextArea
        v-if="matchType === 'keyword'"
        v-model="searchTerms"
        :label="t('AUDITORIA_CATEGORIES.FORM.SEARCH_TERMS_LABEL')"
        :placeholder="t('AUDITORIA_CATEGORIES.FORM.SEARCH_TERMS_PLACEHOLDER')"
        :max-length="2000"
      />
      <TextArea
        v-else
        v-model="instructions"
        :label="t('AUDITORIA_CATEGORIES.FORM.INSTRUCTIONS_LABEL')"
        :placeholder="t('AUDITORIA_CATEGORIES.FORM.INSTRUCTIONS_PLACEHOLDER')"
        :max-length="2000"
      />
      <div class="flex items-center gap-2">
        <input id="category-is-active" v-model="isActive" type="checkbox" />
        <label for="category-is-active">
          {{ t('AUDITORIA_CATEGORIES.FORM.IS_ACTIVE_LABEL') }}
        </label>
      </div>
      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          type="button"
          :label="t('AUDITORIA_CATEGORIES.FORM.CANCEL')"
          @click="onClose"
        />
        <Button
          type="submit"
          :label="
            isEditMode
              ? t('AUDITORIA_CATEGORIES.FORM.SAVE')
              : t('AUDITORIA_CATEGORIES.FORM.CREATE')
          "
          :is-loading="isSaving"
          :disabled="isFormInvalid"
        />
      </div>
    </form>
  </div>
</template>
