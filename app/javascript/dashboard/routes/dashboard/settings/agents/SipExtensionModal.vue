<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';
import sipIdentitiesAPI from 'dashboard/api/sipIdentities';

const props = defineProps({
  agentId: { type: Number, required: true },
  agentName: { type: String, required: true },
  sipExtension: { type: String, default: '' },
  sipActive: { type: Boolean, default: true },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();

const extension = ref(props.sipExtension || '');
const password = ref('');
const active = ref(props.sipActive !== false);
const isSaving = ref(false);

watch(
  () => props.sipExtension,
  val => {
    extension.value = val || '';
  }
);
watch(
  () => props.sipActive,
  val => {
    active.value = val !== false;
  }
);

const save = async () => {
  isSaving.value = true;
  try {
    const payload = {
      sip_extension: extension.value,
      sip_active: active.value,
    };
    if (password.value) payload.sip_password = password.value;

    const { data } = await sipIdentitiesAPI.update(props.agentId, payload);
    useAlert(t('VOICE_TELEPHONY.SIP_SETTINGS_SAVED'));
    emit('saved', { agentId: props.agentId, ...data });
    emit('close');
  } catch (e) {
    useAlert(e?.response?.data?.error || t('VOICE_TELEPHONY.SIP_SAVE_ERROR'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="$t('VOICE_TELEPHONY.EDIT_SIP_EXTENSION')"
      :header-content="agentName"
    />
    <form class="w-full" @submit.prevent="save">
      <div class="w-full">
        <label>
          {{ $t('VOICE_TELEPHONY.SIP_EXTENSION') }}
          <input
            v-model="extension"
            type="text"
            inputmode="numeric"
            :placeholder="$t('VOICE_TELEPHONY.SIP_EXTENSION_PLACEHOLDER')"
          />
        </label>
      </div>
      <div class="w-full">
        <label>
          {{ $t('VOICE_TELEPHONY.SIP_PASSWORD') }}
          <input
            v-model="password"
            type="password"
            :placeholder="$t('VOICE_TELEPHONY.SIP_PASSWORD_PLACEHOLDER')"
            autocomplete="new-password"
          />
        </label>
      </div>
      <div class="w-full flex items-center gap-3 mb-4">
        <label class="flex items-center gap-2 cursor-pointer">
          <input v-model="active" type="checkbox" />
          <span class="text-sm text-n-slate-11">
            {{ $t('VOICE_TELEPHONY.SIP_ACTIVE') }}
          </span>
        </label>
      </div>
      <div class="flex justify-end gap-2 px-0 py-2">
        <Button
          faded
          slate
          type="reset"
          :label="$t('AGENT_MGMT.EDIT.CANCEL_BUTTON_TEXT')"
          @click.prevent="emit('close')"
        />
        <Button
          type="submit"
          :label="$t('AGENT_MGMT.EDIT.FORM.SUBMIT')"
          :is-loading="isSaving"
        />
      </div>
    </form>
  </div>
</template>
