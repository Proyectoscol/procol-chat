<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AuditoriaAiFieldConfigsAPI from 'dashboard/api/auditoriaAiFieldConfigs';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import AiUsageSection from './AiUsageSection.vue';

const { t } = useI18n();

const isLoading = ref(false);
const savingId = ref(null);
const fieldConfigs = ref([]);

const tabs = computed(() => [
  { label: t('AUDITORIA_AI_FIELD_CONFIGS.TAB_LABEL') },
  { label: t('AUDITORIA_AI_USAGE.TAB_LABEL') },
]);
const activeTab = ref(0);
const onTabChange = tab => {
  activeTab.value = tabs.value.findIndex(t2 => t2.label === tab.label);
};

const fetchFieldConfigs = async () => {
  isLoading.value = true;
  try {
    const response = await AuditoriaAiFieldConfigsAPI.get();
    fieldConfigs.value = response.data;
  } catch (error) {
    useAlert(t('AUDITORIA_AI_FIELD_CONFIGS.FETCH_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const saveFieldConfig = async config => {
  savingId.value = config.id;
  try {
    await AuditoriaAiFieldConfigsAPI.update(config.id, {
      title: config.title,
      subtitle: config.subtitle,
    });
    useAlert(t('AUDITORIA_AI_FIELD_CONFIGS.SAVE_SUCCESS'));
  } catch (error) {
    useAlert(t('AUDITORIA_AI_FIELD_CONFIGS.SAVE_ERROR'));
  } finally {
    savingId.value = null;
  }
};

onMounted(fetchFieldConfigs);
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    :loading-message="t('AUDITORIA_AI_FIELD_CONFIGS.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('AUDITORIA_AI_FIELD_CONFIGS.HEADER')"
        :description="t('AUDITORIA_AI_FIELD_CONFIGS.DESCRIPTION')"
      />
    </template>
    <template #body>
      <TabBar
        :tabs="tabs"
        :initial-active-tab="activeTab"
        @tab-changed="onTabChange"
      />
      <div v-if="activeTab === 0" class="flex flex-col gap-4 max-w-2xl mt-4">
        <div
          v-for="config in fieldConfigs"
          :key="config.id"
          class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-1"
        >
          <Input
            :id="`field-title-${config.id}`"
            v-model="config.title"
            :label="t('AUDITORIA_AI_FIELD_CONFIGS.FIELD_TITLE_LABEL')"
          />
          <TextArea
            :id="`field-subtitle-${config.id}`"
            v-model="config.subtitle"
            :label="t('AUDITORIA_AI_FIELD_CONFIGS.FIELD_SUBTITLE_LABEL')"
            :max-length="500"
          />
          <Button
            :label="t('AUDITORIA_AI_FIELD_CONFIGS.SAVE_BUTTON')"
            size="sm"
            class="self-end"
            :is-loading="savingId === config.id"
            @click="saveFieldConfig(config)"
          />
        </div>
      </div>
      <AiUsageSection v-else class="mt-4" />
    </template>
  </SettingsLayout>
</template>
