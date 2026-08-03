<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useEventListener } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import ContactAPI from 'dashboard/api/contacts';
import { useReportDrilldown } from '../../settings/reports/composables/useReportDrilldown';
import ContactListItem from './ContactListItem.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: '' },
  since: { type: Number, default: null },
  until: { type: Number, default: null },
  filters: { type: Object, default: () => ({}) },
  inboxId: { type: String, default: '' },
  labelTitles: { type: Array, default: () => [] },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const drawerRef = ref(null);

const {
  records,
  meta,
  isFetching,
  isFetchingMore,
  hasError,
  hasRecords,
  hasMore,
  open: openDrilldown,
  close,
  loadMore,
} = useReportDrilldown(params => ContactAPI.leadStatsContacts(params));

let previousActiveElement = null;

const isOpen = computed(() => props.open);

const totalCountLabel = computed(() => {
  if (!meta.value.total_count) return '';
  return t('CONTACT_STATS.DRAWER.RESULT_COUNT', {
    count: meta.value.total_count,
  });
});

const restoreFocus = () => {
  if (previousActiveElement?.isConnected) {
    previousActiveElement.focus();
  }
  previousActiveElement = null;
};

const closeDrawer = () => {
  close();
  emit('close');
  restoreFocus();
};

const rememberActiveElement = () => {
  if (previousActiveElement) return;

  previousActiveElement =
    document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
};

const focusDrawer = () => {
  nextTick(() => drawerRef.value?.focus());
};

const fetchContacts = () => {
  openDrilldown({
    since: props.since,
    until: props.until,
    filters: props.filters,
    inboxId: props.inboxId,
    labelTitles: props.labelTitles,
  });
};

const onKeydown = event => {
  if (!isOpen.value) return;

  if (event.key === 'Escape') {
    event.preventDefault();
    event.stopPropagation();
    closeDrawer();
  }
};

useEventListener(document, 'keydown', onKeydown);

watch(
  () => props.open,
  isDrawerOpen => {
    if (!isDrawerOpen) {
      close();
      restoreFocus();
      return;
    }

    rememberActiveElement();
    fetchContacts();
    focusDrawer();
  },
  { immediate: true }
);

watch(
  () => [
    props.since,
    props.until,
    props.filters,
    props.inboxId,
    props.labelTitles,
  ],
  () => {
    if (props.open) fetchContacts();
  },
  { deep: true }
);

onBeforeUnmount(() => {
  restoreFocus();
});
</script>

<template>
  <TeleportWithDirection to="body">
    <Transition name="report-drilldown-fade">
      <div
        v-if="isOpen"
        class="fixed inset-0 z-50 bg-black/30"
        role="presentation"
        @click.self="closeDrawer"
      >
        <aside
          ref="drawerRef"
          class="fixed inset-y-0 end-0 flex w-full max-w-xl flex-col bg-n-solid-1 shadow-xl outline outline-1 outline-n-container"
          role="dialog"
          aria-modal="true"
          :aria-label="title || t('CONTACT_STATS.DRAWER.TITLE')"
          tabindex="-1"
        >
          <header
            class="flex items-start justify-between gap-4 border-b border-n-weak px-6 py-5"
          >
            <div class="min-w-0">
              <h2 class="truncate text-base font-medium text-n-slate-12">
                {{ title || t('CONTACT_STATS.DRAWER.TITLE') }}
              </h2>
              <p v-if="totalCountLabel" class="mt-1 text-sm text-n-slate-11">
                {{ totalCountLabel }}
              </p>
            </div>
            <Button
              ghost
              slate
              size="sm"
              icon="i-lucide-x"
              :aria-label="t('CONTACT_STATS.DRAWER.CLOSE')"
              @click="closeDrawer"
            />
          </header>

          <div class="min-h-0 flex-1 overflow-y-auto px-5 py-3">
            <div
              v-if="isFetching"
              class="flex h-40 items-center justify-center"
            >
              <Spinner />
            </div>

            <div
              v-else-if="hasError"
              class="flex h-40 items-center justify-center text-sm text-n-ruby-11"
            >
              {{ t('CONTACT_STATS.DRAWER.ERROR') }}
            </div>

            <div
              v-else-if="!hasRecords"
              class="flex h-40 items-center justify-center text-sm text-n-slate-10"
            >
              {{ t('CONTACT_STATS.DRAWER.EMPTY') }}
            </div>

            <div v-else class="flex flex-col gap-2">
              <ContactListItem
                v-for="contact in records"
                :key="contact.id"
                :contact="contact"
              />

              <Button
                v-if="hasMore"
                faded
                slate
                size="sm"
                class="mx-auto mt-2"
                :label="t('CONTACT_STATS.DRAWER.LOAD_MORE')"
                :is-loading="isFetchingMore"
                @click="loadMore"
              />
            </div>
          </div>
        </aside>
      </div>
    </Transition>
  </TeleportWithDirection>
</template>
