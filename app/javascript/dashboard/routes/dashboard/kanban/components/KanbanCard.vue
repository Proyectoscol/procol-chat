<script setup>
import { ref, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  contact: { type: Object, required: true },
});

const router = useRouter();
const { t } = useI18n();

const cardRef = ref(null);
const showDetail = ref(false);
let hoverTimer = null;
const tooltipStyle = ref({});

const initials = computed(() => {
  const name = props.contact.name || '';
  return (
    name
      .split(' ')
      .slice(0, 2)
      .map(n => n[0])
      .join('')
      .toUpperCase() || '?'
  );
});

const hasNotes = computed(
  () => props.contact.additional_attributes?.notes_count > 0
);

const formattedDate = computed(() => {
  if (!props.contact.last_activity_at) return null;
  return new Date(props.contact.last_activity_at * 1000).toLocaleDateString();
});

const updateTooltipPosition = () => {
  if (!cardRef.value) return;
  const rect = cardRef.value.getBoundingClientRect();
  const spaceOnRight = window.innerWidth - rect.right;
  const left = spaceOnRight >= 272 ? rect.right + 8 : rect.left - 272 - 8;
  tooltipStyle.value = {
    position: 'fixed',
    top: `${Math.min(rect.top, window.innerHeight - 260)}px`,
    left: `${Math.max(8, left)}px`,
  };
};

const onMouseEnter = () => {
  hoverTimer = setTimeout(() => {
    updateTooltipPosition();
    showDetail.value = true;
  }, 800);
};

const onMouseLeave = () => {
  clearTimeout(hoverTimer);
  showDetail.value = false;
};

const goToContact = e => {
  e.stopPropagation();
  router.push({
    name: 'contacts_edit',
    params: { contactId: props.contact.id },
  });
};
</script>

<template>
  <div
    ref="cardRef"
    class="bg-n-background rounded-lg border border-n-weak p-3 cursor-grab active:cursor-grabbing hover:border-n-slate-4 hover:shadow-sm transition-all select-none group"
    @mouseenter="onMouseEnter"
    @mouseleave="onMouseLeave"
  >
    <div class="flex items-start gap-2.5">
      <div class="flex-shrink-0">
        <img
          v-if="contact.thumbnail"
          :src="contact.thumbnail"
          :alt="contact.name"
          class="size-8 rounded-full object-cover"
        />
        <div
          v-else
          class="size-8 rounded-full bg-n-brand/10 text-n-brand text-xs font-semibold flex items-center justify-center"
        >
          {{ initials }}
        </div>
      </div>

      <div class="min-w-0 flex-1">
        <p class="text-sm font-medium text-n-slate-12 truncate leading-tight">
          {{ contact.name || t('KANBAN.CARD.NO_NAME') }}
        </p>
        <p
          v-if="contact.phone_number"
          class="text-xs text-n-slate-10 truncate mt-0.5"
        >
          {{ contact.phone_number }}
        </p>
        <p
          v-else-if="contact.email"
          class="text-xs text-n-slate-10 truncate mt-0.5"
        >
          {{ contact.email }}
        </p>
      </div>

      <div class="flex items-center gap-1 flex-shrink-0">
        <span
          v-if="hasNotes"
          class="i-lucide-sticky-note size-3 text-n-slate-10"
          :title="t('KANBAN.CARD.HAS_NOTES')"
        />
        <button
          class="p-0.5 rounded opacity-0 group-hover:opacity-100 hover:bg-n-alpha-2 text-n-slate-10 hover:text-n-slate-12 transition-all"
          :title="t('KANBAN.CARD.VIEW_CONTACT')"
          @click="goToContact"
        >
          <span class="i-lucide-external-link size-3.5" />
        </button>
      </div>
    </div>

    <Teleport to="body">
      <div
        v-if="showDetail"
        :style="tooltipStyle"
        class="z-[9999] w-64 bg-n-background border border-n-weak rounded-xl shadow-xl p-4 text-sm pointer-events-none"
      >
        <div class="flex items-center gap-3 mb-3">
          <img
            v-if="contact.thumbnail"
            :src="contact.thumbnail"
            :alt="contact.name"
            class="size-10 rounded-full object-cover flex-shrink-0"
          />
          <div
            v-else
            class="size-10 rounded-full bg-n-brand/10 text-n-brand font-semibold flex items-center justify-center flex-shrink-0 text-sm"
          >
            {{ initials }}
          </div>
          <div class="min-w-0">
            <p class="font-semibold text-n-slate-12 truncate">
              {{ contact.name || t('KANBAN.CARD.NO_NAME') }}
            </p>
            <p v-if="contact.email" class="text-xs text-n-slate-10 truncate">
              {{ contact.email }}
            </p>
          </div>
        </div>

        <div class="flex flex-col gap-1.5 text-xs text-n-slate-11">
          <div v-if="contact.phone_number" class="flex items-center gap-2">
            <span
              class="i-lucide-phone size-3.5 flex-shrink-0 text-n-slate-10"
            />
            <span class="truncate">{{ contact.phone_number }}</span>
          </div>
          <div v-if="contact.email" class="flex items-center gap-2">
            <span
              class="i-lucide-mail size-3.5 flex-shrink-0 text-n-slate-10"
            />
            <span class="truncate">{{ contact.email }}</span>
          </div>
          <div v-if="formattedDate" class="flex items-center gap-2">
            <span
              class="i-lucide-clock size-3.5 flex-shrink-0 text-n-slate-10"
            />
            <span
              >{{ t('KANBAN.CARD.LAST_ACTIVITY') }} {{ formattedDate }}</span
            >
          </div>
        </div>

        <div
          class="mt-3 pt-3 border-t border-n-weak flex items-center gap-1.5 text-xs text-n-brand font-medium"
        >
          <span class="i-lucide-external-link size-3.5" />
          {{ t('KANBAN.CARD.VIEW_PROFILE') }}
        </div>
      </div>
    </Teleport>
  </div>
</template>
