<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
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
const allCategories = useMapGetter('auditoriaCategories/getCategories');

const isEditMode = computed(() => !!props.category);
// Una categoria que YA tiene subcategorias es pura agrupacion visual (ver
// Auditoria::Category.leaf) -- oculta sus propios campos de match (dejaron
// de importar) y no puede a su vez tener padre (maximo 2 niveles).
const isGroupingCategory = computed(() => !!props.category?.has_subcategories);

const title = ref('');
const matchType = ref('keyword');
const isActive = ref(true);
const searchTerms = ref('');
const instructions = ref('');
const parentId = ref('');
const isSaving = ref(false);

const matchTypeOptions = computed(() => [
  {
    value: 'keyword',
    label: t('AUDITORIA_CATEGORIES.FORM.MATCH_TYPE.KEYWORD'),
  },
  { value: 'ai', label: t('AUDITORIA_CATEGORIES.FORM.MATCH_TYPE.AI') },
]);

// Solo categorias de nivel superior (sin padre propio) pueden ser elegidas
// como padre -- garantiza maximo 2 niveles sin necesitar deteccion de
// ciclos. Una categoria no puede ser su propio padre.
const parentOptions = computed(() => [
  { value: '', label: t('AUDITORIA_CATEGORIES.FORM.PARENT_NONE') },
  ...allCategories.value
    .filter(c => !c.parent_id && c.id !== props.category?.id)
    .map(c => ({ value: c.id, label: c.title })),
]);

const setFormValues = () => {
  title.value = props.category?.title || '';
  matchType.value = props.category?.match_type || 'keyword';
  isActive.value = props.category ? props.category.is_active : true;
  searchTerms.value = props.category?.search_terms || '';
  instructions.value = props.category?.instructions || '';
  parentId.value = props.category?.parent_id ?? '';
};
watch(() => props.category, setFormValues, { immediate: true });

const isFormInvalid = computed(() => !title.value.trim());

const onClose = () => emit('close');

const submit = async () => {
  isSaving.value = true;
  // search_terms/instructions se mandan tal cual, sin vaciar el que no
  // esta activo -- match_type ya decide cual se usa para matchear (ver
  // Auditoria::KeywordCategoryMatcherService/ConversationAnalyzerCategoryMatching),
  // asi que vaciar el otro aqui solo perdia datos si el usuario cambiaba
  // de tipo para explorar y volvia a guardar con el tipo original.
  const payload = {
    title: title.value,
    match_type: matchType.value,
    is_active: isActive.value,
    search_terms: searchTerms.value,
    instructions: instructions.value,
    parent_id: isGroupingCategory.value ? null : parentId.value || null,
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
    <!--
      !self-stretch: Modal.vue trae un CSS global (sin scoped) que aplica
      align-self:center a CUALQUIER <form> dentro de .modal-container -- sin
      este override, el form deja de estirarse al ancho fijo del modal y
      pasa a encogerse al contenido (shrink-to-fit), cuyo resultado depende
      de que tan ancho sea el texto actual del Select (por eso el modal se
      veia mas angosto solo al cambiar a "Clasificacion con IA"/mas texto).
    -->
    <form
      class="flex flex-col gap-4 px-4 pb-4 w-full !self-stretch"
      @submit.prevent="submit"
    >
      <Input
        v-model="title"
        :label="t('AUDITORIA_CATEGORIES.FORM.TITLE_LABEL')"
        :placeholder="t('AUDITORIA_CATEGORIES.FORM.TITLE_PLACEHOLDER')"
      />
      <div v-if="!isGroupingCategory" class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('AUDITORIA_CATEGORIES.FORM.PARENT_LABEL') }}
        </label>
        <Select v-model="parentId" :options="parentOptions" />
      </div>
      <p
        v-if="isGroupingCategory"
        class="text-sm text-n-slate-11 rounded-lg bg-n-alpha-1 p-3"
      >
        {{ t('AUDITORIA_CATEGORIES.FORM.GROUPING_NOTE') }}
      </p>
      <template v-else>
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
      </template>
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
