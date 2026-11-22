<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import MessageTemplateFormModal from '../components/MessageTemplateFormModal.vue';

const { t } = useI18n();
const store = useStore();

const templates = useMapGetter('calendarioMessageTemplates/getTemplates');
const uiFlags = useMapGetter('calendarioMessageTemplates/getUIFlags');

const showFormModal = ref(false);
const formPresetKey = ref('');
const formPrefillLabel = ref('');
const formPrefillBody = ref('');
const formPrefillQuickReplies = ref([]);

const showDeletePopup = ref(false);
const deletingTemplate = ref(null);
const activatingId = ref(null);

// Un set por key en vez de un booleano global -- cada tarjeta expande su
// historial de forma independiente.
const expandedKeys = reactive({});
const toggleExpanded = key => {
  expandedKeys[key] = !expandedKeys[key];
};

// Agrupado por key, cada grupo con sus versiones ordenadas mas nueva
// primero y la version activa separada aparte para la vista resumida de la
// tarjeta (si por algun motivo ninguna esta activa, se usa la mas nueva).
const groups = computed(() => {
  const byKey = new Map();
  templates.value.forEach(template => {
    if (!byKey.has(template.key)) byKey.set(template.key, []);
    byKey.get(template.key).push(template);
  });
  return [...byKey.entries()].map(([key, versions]) => {
    const sorted = [...versions].sort((a, b) => b.version - a.version);
    const active = sorted.find(version => version.status === 'active');
    return {
      key,
      label: sorted[0]?.label,
      versions: sorted,
      active: active || sorted[0],
    };
  });
});

const openCreateModal = () => {
  formPresetKey.value = '';
  formPrefillLabel.value = '';
  formPrefillBody.value = '';
  formPrefillQuickReplies.value = [];
  showFormModal.value = true;
};

const openNewVersionModal = group => {
  formPresetKey.value = group.key;
  formPrefillLabel.value = group.active.label;
  formPrefillBody.value = group.active.body;
  formPrefillQuickReplies.value = group.active.quick_replies || [];
  showFormModal.value = true;
};

const closeFormModal = () => {
  showFormModal.value = false;
};

const activateVersion = async version => {
  activatingId.value = version.id;
  try {
    await store.dispatch('calendarioMessageTemplates/activate', version.id);
    useAlert(t('CALENDARIO.TEMPLATE_LIBRARY.ACTIVATE_SUCCESS'));
  } catch (error) {
    useAlert(t('CALENDARIO.TEMPLATE_LIBRARY.ACTIVATE_ERROR'));
  } finally {
    activatingId.value = null;
  }
};

const openDeletePopup = version => {
  deletingTemplate.value = version;
  showDeletePopup.value = true;
};
const closeDeletePopup = () => {
  showDeletePopup.value = false;
};
const confirmDeletion = async () => {
  const id = deletingTemplate.value.id;
  closeDeletePopup();
  try {
    await store.dispatch('calendarioMessageTemplates/delete', id);
    useAlert(t('CALENDARIO.TEMPLATE_LIBRARY.DELETE_SUCCESS'));
  } catch (error) {
    useAlert(t('CALENDARIO.TEMPLATE_LIBRARY.DELETE_ERROR'));
  }
};

onMounted(async () => {
  try {
    await store.dispatch('calendarioMessageTemplates/get');
  } catch (error) {
    useAlert(t('CALENDARIO.TEMPLATE_LIBRARY.FETCH_ERROR'));
  }
});
</script>

<template>
  <div v-if="uiFlags.isFetching" class="flex items-center justify-center py-8">
    <Spinner />
  </div>
  <div v-else class="flex flex-col gap-4">
    <div class="flex items-center justify-between">
      <p class="text-sm text-n-slate-11 max-w-2xl">
        {{ t('CALENDARIO.TEMPLATE_LIBRARY.DESCRIPTION') }}
      </p>
      <Button
        :label="t('CALENDARIO.TEMPLATE_LIBRARY.ADD_BUTTON')"
        size="sm"
        @click="openCreateModal"
      />
    </div>

    <p v-if="!groups.length" class="text-sm text-n-slate-10 py-6 text-center">
      {{ t('CALENDARIO.TEMPLATE_LIBRARY.EMPTY') }}
    </p>

    <div
      v-for="group in groups"
      :key="group.key"
      class="flex flex-col gap-3 rounded-lg border border-n-weak p-4"
    >
      <div class="flex items-start justify-between gap-3">
        <div class="flex flex-col gap-0.5">
          <span class="text-sm font-medium text-n-slate-12">
            {{ group.label }}
          </span>
          <span class="text-xs text-n-slate-10 font-mono">{{ group.key }}</span>
        </div>
        <div class="flex items-center gap-1.5 flex-shrink-0">
          <span
            class="text-[10px] font-medium rounded px-1.5 py-0.5 bg-n-teal-3 text-n-teal-11"
          >
            {{
              t('CALENDARIO.TEMPLATE_LIBRARY.VERSION_LABEL', {
                version: group.active.version,
              })
            }}
            · {{ t('CALENDARIO.TEMPLATE_LIBRARY.STATUS.ACTIVE') }}
          </span>
        </div>
      </div>

      <p
        class="text-sm whitespace-pre-wrap text-n-slate-12 bg-n-alpha-black2 rounded-lg p-3"
      >
        {{ group.active.body }}
      </p>

      <div class="flex items-center justify-between">
        <button
          type="button"
          class="text-xs text-n-blue-text hover:underline"
          @click="toggleExpanded(group.key)"
        >
          {{
            expandedKeys[group.key]
              ? t('CALENDARIO.TEMPLATE_LIBRARY.HIDE_VERSIONS')
              : t('CALENDARIO.TEMPLATE_LIBRARY.VIEW_VERSIONS', {
                  count: group.versions.length,
                })
          }}
        </button>
        <Button
          faded
          slate
          sm
          :label="t('CALENDARIO.TEMPLATE_LIBRARY.ADD_VERSION_BUTTON')"
          @click="openNewVersionModal(group)"
        />
      </div>

      <div
        v-if="expandedKeys[group.key]"
        class="flex flex-col gap-2 border-t border-n-weak pt-3"
      >
        <div
          v-for="version in group.versions"
          :key="version.id"
          class="flex flex-col gap-2 rounded-lg p-3"
          :class="
            version.status === 'active' ? 'bg-n-teal-2' : 'bg-n-alpha-black2'
          "
        >
          <div class="flex items-center justify-between">
            <span class="text-xs font-medium text-n-slate-11">
              {{
                t('CALENDARIO.TEMPLATE_LIBRARY.VERSION_LABEL', {
                  version: version.version,
                })
              }}
              ·
              {{
                version.status === 'active'
                  ? t('CALENDARIO.TEMPLATE_LIBRARY.STATUS.ACTIVE')
                  : t('CALENDARIO.TEMPLATE_LIBRARY.STATUS.DRAFT')
              }}
            </span>
            <div v-if="version.status === 'draft'" class="flex gap-1.5">
              <Button
                faded
                slate
                sm
                :is-loading="activatingId === version.id"
                :label="t('CALENDARIO.TEMPLATE_LIBRARY.ACTIVATE_BUTTON')"
                @click="activateVersion(version)"
              />
              <Button
                icon="i-woot-bin"
                faded
                ruby
                sm
                @click="openDeletePopup(version)"
              />
            </div>
          </div>
          <p class="text-sm whitespace-pre-wrap text-n-slate-12">
            {{ version.body }}
          </p>
          <p
            v-if="version.quick_replies?.length"
            class="text-xs text-n-slate-10"
          >
            {{ version.quick_replies.join(' · ') }}
          </p>
          <p v-if="version.notes" class="text-xs text-n-slate-10 italic">
            {{ t('CALENDARIO.TEMPLATE_LIBRARY.NOTES_LABEL') }}:
            {{ version.notes }}
          </p>
        </div>
      </div>
    </div>

    <woot-modal v-model:show="showFormModal" :on-close="closeFormModal">
      <MessageTemplateFormModal
        :preset-key="formPresetKey"
        :prefill-label="formPrefillLabel"
        :prefill-body="formPrefillBody"
        :prefill-quick-replies="formPrefillQuickReplies"
        @close="closeFormModal"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeletePopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('CALENDARIO.TEMPLATE_LIBRARY.DELETE_CONFIRM.TITLE')"
      :message="t('CALENDARIO.TEMPLATE_LIBRARY.DELETE_CONFIRM.MESSAGE')"
      :confirm-text="t('CALENDARIO.TEMPLATE_LIBRARY.DELETE_CONFIRM.CONFIRM')"
      :reject-text="t('CALENDARIO.TEMPLATE_LIBRARY.DELETE_CONFIRM.CANCEL')"
    />
  </div>
</template>
