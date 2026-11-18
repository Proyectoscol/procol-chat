<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { isWhatsAppCapableInbox } from 'dashboard/helper/inbox';
import Select from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  flow: { type: Object, default: null },
});
const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const allInboxes = useMapGetter('inboxes/getInboxes');
const whatsappInboxes = computed(() =>
  allInboxes.value.filter(isWhatsAppCapableInbox)
);

const isEditMode = computed(() => !!props.flow);

const name = ref('');
const inboxId = ref('');
const matchType = ref('default');
const matchValue = ref('');
const priority = ref(0);
const active = ref(true);
const isSaving = ref(false);

// Cada paso en memoria guarda las opciones como texto (una por linea) para
// que el textarea sea editable sin reconstruir el array en cada tecla --
// se parte a un array real solo al enviar (ver stepsForSubmit).
const steps = ref([]);

// Si tiene condicion, en memoria vive como { enabled, stepIndex, equals }
// en vez del {step, equals} crudo que espera el backend -- mas facil de
// atar a los selects del formulario; se reconstruye al enviar.
const makeStep = () => ({
  ask: '',
  optionsText: '',
  condition: { enabled: false, stepIndex: 0, equals: '' },
});

const setFormValues = () => {
  name.value = props.flow?.name || '';
  inboxId.value = props.flow?.inbox_id || '';
  matchType.value = props.flow?.match_type || 'default';
  matchValue.value = props.flow?.match_value || '';
  priority.value = props.flow?.priority ?? 0;
  active.value = props.flow ? props.flow.active : true;
  steps.value = (props.flow?.steps || []).map(step => ({
    ask: step.ask || '',
    optionsText: (step.options || []).join('\n'),
    condition: step.if
      ? { enabled: true, stepIndex: step.if.step, equals: step.if.equals }
      : { enabled: false, stepIndex: 0, equals: '' },
  }));
  if (!steps.value.length) steps.value.push(makeStep());
};
watch(() => props.flow, setFormValues, { immediate: true });

onMounted(() => {
  store.dispatch('inboxes/get');
});

const matchTypeOptions = computed(() => [
  {
    value: 'default',
    label: t('CALENDARIO.WELCOME_BOT.FORM.MATCH_TYPE_OPTIONS.DEFAULT'),
  },
  {
    value: 'keyword',
    label: t('CALENDARIO.WELCOME_BOT.FORM.MATCH_TYPE_OPTIONS.KEYWORD'),
  },
]);

const inboxOptions = computed(() => [
  { value: '', label: t('CALENDARIO.WELCOME_BOT.FORM.INBOX_PLACEHOLDER') },
  ...whatsappInboxes.value.map(inbox => ({
    value: inbox.id,
    label: inbox.name,
  })),
]);

const addStep = () => {
  steps.value.push(makeStep());
};
const removeStep = index => {
  steps.value.splice(index, 1);
  // Cualquier condicion que apuntara a un paso borrado (o posterior, que
  // cambio de indice) queda inconsistente -- se desactiva, el usuario la
  // vuelve a armar si todavia aplica.
  steps.value.forEach(step => {
    if (
      step.condition.enabled &&
      step.condition.stepIndex >= steps.value.length
    ) {
      step.condition.enabled = false;
    }
  });
};

// Las opciones del paso referenciado por la condicion -- si existen, se
// ofrecen como select en vez de que el usuario tenga que escribir el valor
// exacto a mano (y arriesgarse a un typo que nunca matchee).
const conditionOptionsFor = stepIndex => {
  const referenced = steps.value[stepIndex];
  if (!referenced) return [];
  return referenced.optionsText
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean);
};

// El <select> de "equals" muestra la primera opcion seleccionada por
// comportamiento nativo del navegador incluso cuando el v-model sigue en ''
// -- sin esto el valor guardado queda vacio aunque se vea una opcion marcada.
watch(
  steps,
  newSteps => {
    newSteps.forEach(step => {
      if (!step.condition.enabled) return;
      const options = conditionOptionsFor(step.condition.stepIndex);
      if (options.length && !options.includes(step.condition.equals)) {
        step.condition.equals = options[0];
      }
    });
  },
  { deep: true }
);

const isFormInvalid = computed(() => {
  if (!name.value.trim() || !inboxId.value) return true;
  if (matchType.value === 'keyword' && !matchValue.value.trim()) return true;
  if (!steps.value.length) return true;
  return steps.value.some(step => !step.ask.trim());
});

const stepsForSubmit = () =>
  steps.value.map(step => {
    const options = step.optionsText
      .split('\n')
      .map(line => line.trim())
      .filter(Boolean);
    const payload = { ask: step.ask.trim() };
    if (options.length) payload.options = options;
    if (step.condition.enabled) {
      payload.if = {
        step: step.condition.stepIndex,
        equals: step.condition.equals,
      };
    }
    return payload;
  });

const onClose = () => emit('close');

const submit = async () => {
  isSaving.value = true;
  const payload = {
    name: name.value.trim(),
    inbox_id: inboxId.value,
    match_type: matchType.value,
    match_value: matchType.value === 'keyword' ? matchValue.value.trim() : null,
    priority: Number(priority.value),
    active: active.value,
    steps: stepsForSubmit(),
  };
  try {
    if (isEditMode.value) {
      await store.dispatch('calendarioWelcomeBotFlows/update', {
        id: props.flow.id,
        ...payload,
      });
      useAlert(t('CALENDARIO.WELCOME_BOT.FORM.EDIT_SUCCESS'));
    } else {
      await store.dispatch('calendarioWelcomeBotFlows/create', payload);
      useAlert(t('CALENDARIO.WELCOME_BOT.FORM.CREATE_SUCCESS'));
    }
    onClose();
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CALENDARIO.WELCOME_BOT.FORM.ERROR')
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
          ? t('CALENDARIO.WELCOME_BOT.FORM.EDIT_TITLE')
          : t('CALENDARIO.WELCOME_BOT.FORM.CREATE_TITLE')
      "
    />
    <form
      class="flex flex-col gap-4 px-4 pb-4 w-full !self-stretch"
      @submit.prevent="submit"
    >
      <Input
        v-model="name"
        :label="t('CALENDARIO.WELCOME_BOT.FORM.NAME_LABEL')"
      />

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.WELCOME_BOT.FORM.INBOX_LABEL') }}
        </label>
        <Select v-model="inboxId" :options="inboxOptions" />
      </div>

      <div class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.WELCOME_BOT.FORM.MATCH_TYPE_LABEL') }}
        </label>
        <Select v-model="matchType" :options="matchTypeOptions" />
        <p class="text-xs text-n-slate-10">
          {{ t('CALENDARIO.WELCOME_BOT.FORM.MATCH_TYPE_HINT') }}
        </p>
      </div>

      <Input
        v-if="matchType === 'keyword'"
        v-model="matchValue"
        :label="t('CALENDARIO.WELCOME_BOT.FORM.MATCH_VALUE_LABEL')"
        :placeholder="t('CALENDARIO.WELCOME_BOT.FORM.MATCH_VALUE_PLACEHOLDER')"
      />

      <Input
        v-model="priority"
        type="number"
        :label="t('CALENDARIO.WELCOME_BOT.FORM.PRIORITY_LABEL')"
      />
      <p class="text-xs text-n-slate-10 -mt-3">
        {{ t('CALENDARIO.WELCOME_BOT.FORM.PRIORITY_HINT') }}
      </p>

      <div class="flex flex-col gap-3">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CALENDARIO.WELCOME_BOT.FORM.STEPS_LABEL') }}
        </label>

        <div
          v-for="(step, index) in steps"
          :key="index"
          class="flex flex-col gap-2 rounded-lg border border-n-weak p-3"
        >
          <div class="flex items-center justify-between">
            <span class="text-xs font-medium text-n-slate-11">
              {{
                t('CALENDARIO.WELCOME_BOT.FORM.STEP_NUMBER', {
                  number: index + 1,
                })
              }}
            </span>
            <Button
              v-if="steps.length > 1"
              icon="i-woot-bin"
              slate
              sm
              type="button"
              @click="removeStep(index)"
            />
          </div>

          <Input
            v-model="step.ask"
            :label="t('CALENDARIO.WELCOME_BOT.FORM.STEP_ASK_LABEL')"
          />

          <TextArea
            v-model="step.optionsText"
            :label="t('CALENDARIO.WELCOME_BOT.FORM.STEP_OPTIONS_LABEL')"
            :placeholder="
              t('CALENDARIO.WELCOME_BOT.FORM.STEP_OPTIONS_PLACEHOLDER')
            "
          />

          <div
            v-if="index > 0"
            class="flex flex-col gap-2 border-t border-n-weak pt-2"
          >
            <div class="flex items-center gap-2">
              <input
                :id="`step-condition-${index}`"
                v-model="step.condition.enabled"
                type="checkbox"
              />
              <label
                :for="`step-condition-${index}`"
                class="text-xs text-n-slate-11"
              >
                {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONDITION_LABEL') }}
              </label>
            </div>

            <div
              v-if="step.condition.enabled"
              class="flex flex-wrap items-center gap-2 pl-5"
            >
              <span class="text-xs text-n-slate-11">
                {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONDITION_IF') }}
              </span>
              <Select
                v-model="step.condition.stepIndex"
                :options="
                  Array.from({ length: index }, (_, i) => ({
                    value: i,
                    label: t('CALENDARIO.WELCOME_BOT.FORM.STEP_NUMBER', {
                      number: i + 1,
                    }),
                  }))
                "
              />
              <span class="text-xs text-n-slate-11">
                {{ t('CALENDARIO.WELCOME_BOT.FORM.STEP_CONDITION_EQUALS') }}
              </span>
              <Select
                v-if="conditionOptionsFor(step.condition.stepIndex).length"
                v-model="step.condition.equals"
                :options="
                  conditionOptionsFor(step.condition.stepIndex).map(value => ({
                    value,
                    label: value,
                  }))
                "
              />
              <Input v-else v-model="step.condition.equals" class="!mb-0" />
            </div>
          </div>
        </div>

        <Button
          faded
          slate
          sm
          type="button"
          icon="i-lucide-plus"
          :label="t('CALENDARIO.WELCOME_BOT.FORM.ADD_STEP_BUTTON')"
          @click="addStep"
        />
      </div>

      <div class="flex items-center gap-2">
        <input id="flow-active" v-model="active" type="checkbox" />
        <label for="flow-active">{{
          t('CALENDARIO.WELCOME_BOT.FORM.ACTIVE_LABEL')
        }}</label>
      </div>

      <div class="flex items-center justify-end gap-2">
        <Button
          faded
          slate
          type="button"
          :label="t('CALENDARIO.WELCOME_BOT.FORM.CANCEL')"
          @click="onClose"
        />
        <Button
          type="submit"
          :label="
            isEditMode
              ? t('CALENDARIO.WELCOME_BOT.FORM.SAVE')
              : t('CALENDARIO.WELCOME_BOT.FORM.CREATE')
          "
          :is-loading="isSaving"
          :disabled="isFormInvalid"
        />
      </div>
    </form>
  </div>
</template>
