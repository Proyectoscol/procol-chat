<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';

defineProps({
  attributes: { type: Array, default: () => [] },
});

const emit = defineEmits(['configure']);

const store = useStore();
const { t } = useI18n();

const mode = ref('attribute');
const selectedAttribute = ref(null);
const selectedTagTitles = ref([]);

const labels = useMapGetter('labels/getLabels');

onMounted(() => {
  store.dispatch('attributes/get');
  store.dispatch('labels/get');
});

const selectAttribute = attr => {
  selectedAttribute.value = attr;
};

// Click order is preserved (append/remove by value, never re-sorted) so the
// order the admin picks tags in becomes the column order on the board.
const toggleTag = title => {
  const idx = selectedTagTitles.value.indexOf(title);
  if (idx === -1) {
    selectedTagTitles.value = [...selectedTagTitles.value, title];
  } else {
    selectedTagTitles.value = selectedTagTitles.value.filter(
      selected => selected !== title
    );
  }
};

const canConfirm = computed(() =>
  mode.value === 'tags'
    ? selectedTagTitles.value.length > 0
    : !!selectedAttribute.value
);

const confirm = () => {
  if (!canConfirm.value) return;

  if (mode.value === 'tags') {
    emit('configure', {
      mode: 'tags',
      tagNames: [...selectedTagTitles.value],
    });
    return;
  }

  emit('configure', {
    mode: 'attribute',
    attributeKey: selectedAttribute.value.attributeKey,
    attributeName: selectedAttribute.value.attributeDisplayName,
    attributeValues: selectedAttribute.value.attributeValues || [],
  });
};
</script>

<template>
  <div class="flex flex-col items-center justify-center flex-1 gap-6 p-8">
    <div class="flex flex-col items-center gap-2 text-center">
      <span class="i-lucide-kanban size-10 text-n-brand" />
      <h2 class="text-xl font-semibold text-n-slate-12">
        {{ t('KANBAN.CONFIG.TITLE') }}
      </h2>
      <p class="text-sm text-n-slate-11 max-w-sm">
        {{ t('KANBAN.CONFIG.DESCRIPTION') }}
      </p>
    </div>

    <div class="flex gap-1 p-1 rounded-lg bg-n-alpha-1">
      <button
        class="px-4 py-1.5 rounded-md text-sm font-medium transition-colors"
        :class="
          mode === 'attribute'
            ? 'bg-n-background text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="mode = 'attribute'"
      >
        {{ t('KANBAN.CONFIG.MODE_ATTRIBUTE') }}
      </button>
      <button
        class="px-4 py-1.5 rounded-md text-sm font-medium transition-colors"
        :class="
          mode === 'tags'
            ? 'bg-n-background text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="mode = 'tags'"
      >
        {{ t('KANBAN.CONFIG.MODE_TAGS') }}
      </button>
    </div>

    <template v-if="mode === 'attribute'">
      <div
        v-if="attributes.length === 0"
        class="text-sm text-n-slate-10 text-center max-w-sm"
      >
        {{ t('KANBAN.CONFIG.EMPTY_STATE') }}<br />
        {{ t('KANBAN.CONFIG.EMPTY_CTA') }}
      </div>

      <div v-else class="flex flex-col gap-2 w-full max-w-sm">
        <button
          v-for="attr in attributes"
          :key="attr.attributeKey"
          class="flex items-center gap-3 px-4 py-3 rounded-xl border text-left transition-all"
          :class="
            selectedAttribute?.attributeKey === attr.attributeKey
              ? 'border-n-brand bg-n-brand/5 text-n-slate-12'
              : 'border-n-weak hover:border-n-slate-4 hover:bg-n-alpha-1 text-n-slate-11'
          "
          @click="selectAttribute(attr)"
        >
          <span class="i-lucide-list size-4 flex-shrink-0" />
          <div class="min-w-0 flex-1">
            <div class="text-sm font-medium truncate">
              {{ attr.attributeDisplayName }}
            </div>
            <div class="text-xs text-n-slate-10 truncate mt-0.5">
              {{ (attr.attributeValues || []).join(' · ') }}
            </div>
          </div>
          <span
            v-if="selectedAttribute?.attributeKey === attr.attributeKey"
            class="i-lucide-check size-4 text-n-brand flex-shrink-0"
          />
        </button>
      </div>
    </template>

    <template v-else>
      <div
        v-if="labels.length === 0"
        class="text-sm text-n-slate-10 text-center max-w-sm"
      >
        {{ t('KANBAN.CONFIG.EMPTY_TAGS_STATE') }}
      </div>

      <div v-else class="flex flex-col gap-2 w-full max-w-sm">
        <p class="text-xs text-n-slate-10">
          {{ t('KANBAN.CONFIG.TAGS_HINT') }}
        </p>
        <button
          v-for="label in labels"
          :key="label.id"
          class="flex items-center gap-3 px-4 py-3 rounded-xl border text-left transition-all"
          :class="
            selectedTagTitles.includes(label.title)
              ? 'border-n-brand bg-n-brand/5 text-n-slate-12'
              : 'border-n-weak hover:border-n-slate-4 hover:bg-n-alpha-1 text-n-slate-11'
          "
          @click="toggleTag(label.title)"
        >
          <span
            class="size-2.5 rounded-full flex-shrink-0"
            :style="{ backgroundColor: label.color }"
          />
          <div class="min-w-0 flex-1 text-sm font-medium truncate">
            {{ label.title }}
          </div>
          <span
            v-if="selectedTagTitles.includes(label.title)"
            class="text-xs font-semibold text-n-brand flex-shrink-0"
          >
            {{ selectedTagTitles.indexOf(label.title) + 1 }}
          </span>
        </button>
      </div>
    </template>

    <button
      v-if="
        (mode === 'attribute' && attributes.length > 0) ||
        (mode === 'tags' && labels.length > 0)
      "
      :disabled="!canConfirm"
      class="px-6 py-2 rounded-lg text-sm font-medium transition-colors"
      :class="
        canConfirm
          ? 'bg-n-brand text-white hover:bg-n-brand/90 cursor-pointer'
          : 'bg-n-alpha-2 text-n-slate-10 cursor-not-allowed'
      "
      @click="confirm"
    >
      {{ t('KANBAN.CONFIG.CREATE_BUTTON') }}
    </button>
  </div>
</template>
