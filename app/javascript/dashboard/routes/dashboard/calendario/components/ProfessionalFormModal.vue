<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  professional: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();
const agents = useMapGetter('agents/getAgents');
const specialties = useMapGetter('calendarioSpecialties/getSpecialties');

const isEditMode = computed(() => !!props.professional);

const name = ref('');
const active = ref(true);
const userId = ref('');
const specialtyId = ref('');
const isSaving = ref(false);

const agentOptions = computed(() => [
  { value: '', label: t('CALENDARIO.PROFESSIONALS.FORM.NO_AGENT') },
  ...agents.value.map(agent => ({ value: agent.id, label: agent.name })),
]);

const specialtyOptions = computed(() => [
  {
    value: '',
    label: t('CALENDARIO.PROFESSIONALS.FORM.SPECIALTY_PLACEHOLDER'),
  },
  ...specialties.value.map(specialty => ({
    value: specialty.id,
    label: specialty.name,
  })),
]);

const setFormValues = () => {
  name.value = props.professional?.name || '';
  active.value = props.professional ? props.professional.active : true;
  userId.value = props.professional?.user_id ?? '';
  specialtyId.value = props.professional?.specialty_id ?? '';
};
watch(() => props.professional, setFormValues, { immediate: true });

onMounted(() => {
  store.dispatch('calendarioSpecialties/get');
});

const onAgentSelected = () => {
  const agent = agents.value.find(a => a.id === userId.value);
  if (agent && !name.value) name.value = agent.name;
};
watch(userId, onAgentSelected);

const isFormInvalid = computed(() => !name.value.trim() || !specialtyId.value);

const onClose = () => emit('close');

const submit = async () => {
  isSaving.value = true;
  const payload = {
    name: name.value,
    active: active.value,
    user_id: userId.value || null,
    specialty_id: specialtyId.value,
  };
  try {
    if (isEditMode.value) {
      await store.dispatch('calendarioProfessionals/update', {
        id: props.professional.id,
        ...payload,
      });
      useAlert(t('CALENDARIO.PROFESSIONALS.FORM.EDIT_SUCCESS'));
    } else {
      await store.dispatch('calendarioProfessionals/create', payload);
      useAlert(t('CALENDARIO.PROFESSIONALS.FORM.CREATE_SUCCESS'));
    }
    onClose();
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('CALENDARIO.PROFESSIONALS.FORM.ERROR')
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
          ? t('CALENDARIO.PROFESSIONALS.FORM.EDIT_TITLE')
          : t('CALENDARIO.PROFESSIONALS.FORM.CREATE_TITLE')
      "
    />
    <form
      class="flex flex-col gap-4 px-4 pb-4 w-full !self-stretch"
      @submit.prevent="submit"
    >
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.PROFESSIONALS.FORM.AGENT_LABEL') }}
        </label>
        <Select v-model="userId" :options="agentOptions" />
        <p class="text-xs text-n-slate-10">
          {{ t('CALENDARIO.PROFESSIONALS.FORM.AGENT_HINT') }}
        </p>
      </div>
      <Input
        v-model="name"
        :label="t('CALENDARIO.PROFESSIONALS.FORM.NAME_LABEL')"
        :placeholder="t('CALENDARIO.PROFESSIONALS.FORM.NAME_PLACEHOLDER')"
      />
      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.PROFESSIONALS.FORM.SPECIALTY_LABEL') }}
        </label>
        <Select v-model="specialtyId" :options="specialtyOptions" />
      </div>
      <div class="flex flex-col gap-1">
        <div class="flex items-center gap-2">
          <input id="professional-active" v-model="active" type="checkbox" />
          <label for="professional-active">
            {{ t('CALENDARIO.PROFESSIONALS.FORM.ACTIVE_LABEL') }}
          </label>
        </div>
        <p class="text-xs text-n-slate-10">
          {{ t('CALENDARIO.PROFESSIONALS.FORM.ACTIVE_HINT') }}
        </p>
      </div>
      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          type="button"
          :label="t('CALENDARIO.PROFESSIONALS.FORM.CANCEL')"
          @click="onClose"
        />
        <Button
          type="submit"
          :label="
            isEditMode
              ? t('CALENDARIO.PROFESSIONALS.FORM.SAVE')
              : t('CALENDARIO.PROFESSIONALS.FORM.CREATE')
          "
          :is-loading="isSaving"
          :disabled="isFormInvalid"
        />
      </div>
    </form>
  </div>
</template>
