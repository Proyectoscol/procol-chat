<script setup>
import { ref, computed, watch } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import ContactAPI from 'dashboard/api/contacts';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  contact: { type: Object, default: null },
  openInNewTab: { type: Boolean, default: false },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const contactAttributes = useMapGetter('attributes/getContactAttributes');

const dialogRef = ref(null);
const fullContact = ref(null);
const conversations = ref([]);
const isLoading = ref(false);
const isNavigating = ref(false);

const displayContact = computed(() => fullContact.value || props.contact);

const modalTitle = computed(
  () => displayContact.value?.name || t('KANBAN.CARD.NO_NAME')
);

const initials = computed(() => {
  const name = displayContact.value?.name || '';
  return (
    name
      .split(' ')
      .slice(0, 2)
      .map(n => n[0])
      .join('')
      .toUpperCase() || '?'
  );
});

const customAttributesList = computed(() => {
  const attrs = contactAttributes.value || [];
  const raw = displayContact.value?.custom_attributes || {};
  return attrs
    .filter(
      a => raw[a.attributeKey] !== undefined && raw[a.attributeKey] !== ''
    )
    .map(a => ({
      label: a.attributeDisplayName,
      value: String(raw[a.attributeKey]),
    }));
});

const statusLabel = status => {
  const map = {
    open: t('KANBAN.MODAL.OPEN_STATUS'),
    resolved: t('KANBAN.MODAL.RESOLVED_STATUS'),
    pending: t('KANBAN.MODAL.PENDING_STATUS'),
  };
  return map[status] || status;
};

const statusClass = status =>
  ({
    open: 'text-green-600 bg-green-50 dark:bg-green-900/20',
    resolved: 'text-n-slate-10 bg-n-alpha-2',
    pending: 'text-yellow-600 bg-yellow-50 dark:bg-yellow-900/20',
  })[status] || 'text-n-slate-10 bg-n-alpha-2';

const loadDetails = async () => {
  if (!props.contact?.id) return;
  isLoading.value = true;
  fullContact.value = null;
  conversations.value = [];
  try {
    const [contactRes, convRes] = await Promise.all([
      ContactAPI.show(props.contact.id),
      ContactAPI.getConversations(props.contact.id),
    ]);
    fullContact.value = contactRes.data.payload;
    const all = convRes.data?.payload || [];
    conversations.value = [...all].sort(
      (a, b) => (b.last_activity_at || 0) - (a.last_activity_at || 0)
    );
  } catch {
    // show partial data already available via props.contact
  } finally {
    isLoading.value = false;
  }
};

const open = () => {
  loadDetails();
  dialogRef.value?.open();
};

const close = () => {
  dialogRef.value?.close();
  emit('close');
};

defineExpose({ open, close });

watch(
  () => props.contact?.id,
  (id, prevId) => {
    if (id && id !== prevId) loadDetails();
  }
);

const navigateToConversation = conv => {
  const path = frontendURL(
    conversationUrl({ accountId: route.params.accountId, id: conv.id })
  );
  if (props.openInNewTab) {
    window.open(router.resolve({ path }).href, '_blank');
    return;
  }
  close();
  router.push({ path });
};

const goToContact = () => {
  const location = {
    name: 'contacts_edit',
    params: { contactId: displayContact.value?.id },
  };
  if (props.openInNewTab) {
    window.open(router.resolve(location).href, '_blank');
    return;
  }
  close();
  router.push(location);
};

const goToBestConversation = async () => {
  if (isNavigating.value) return;
  isNavigating.value = true;
  try {
    const sorted =
      conversations.value.length > 0
        ? conversations.value
        : (await ContactAPI.getConversations(displayContact.value.id)).data
            ?.payload || [];
    const target = sorted.find(c => c.status === 'open') || sorted[0];
    if (!target) {
      useAlert(t('KANBAN.CARD.NO_CONVERSATION'));
      return;
    }
    navigateToConversation(target);
  } catch {
    useAlert(t('KANBAN.ERRORS.UPDATE_FAILED'));
  } finally {
    isNavigating.value = false;
  }
};
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="modalTitle"
    width="2xl"
    position="center"
    :show-confirm-button="false"
    :show-cancel-button="false"
    overflow-y-auto
    @close="emit('close')"
  >
    <div class="flex flex-col gap-5">
      <!-- Loading -->
      <div
        v-if="isLoading"
        class="flex items-center justify-center py-10 text-sm text-n-slate-10"
      >
        <span class="i-lucide-loader-2 size-4 animate-spin mr-2" />
        {{ t('KANBAN.MODAL.LOADING') }}
      </div>

      <template v-else-if="displayContact">
        <!-- Avatar + identity -->
        <div class="flex items-center gap-4">
          <div class="flex-shrink-0">
            <img
              v-if="displayContact.thumbnail"
              :src="displayContact.thumbnail"
              :alt="displayContact.name"
              class="size-12 rounded-full object-cover"
            />
            <div
              v-else
              class="size-12 rounded-full bg-n-brand/10 text-n-brand text-base font-semibold flex items-center justify-center"
            >
              {{ initials }}
            </div>
          </div>
          <div class="flex-1 min-w-0">
            <p
              v-if="displayContact.email"
              class="text-sm text-n-slate-10 truncate"
            >
              {{ displayContact.email }}
            </p>
            <p
              v-if="displayContact.phone_number"
              class="text-sm text-n-slate-10 truncate"
            >
              {{ displayContact.phone_number }}
            </p>
          </div>
          <!-- Action buttons -->
          <div class="flex items-center gap-2 flex-shrink-0">
            <button
              class="flex items-center gap-1.5 h-8 px-3 rounded-lg text-xs font-medium border border-n-weak hover:bg-n-alpha-2 text-n-slate-11 transition-colors"
              :title="t('KANBAN.CARD.VIEW_CONTACT')"
              @click.stop="goToContact"
            >
              <span class="i-lucide-user size-3.5" />
              {{ t('KANBAN.CARD.VIEW_CONTACT') }}
            </button>
            <button
              class="flex items-center gap-1.5 h-8 px-3 rounded-lg text-xs font-medium border border-n-weak hover:bg-n-alpha-2 text-n-slate-11 transition-colors disabled:opacity-50"
              :disabled="isNavigating"
              :title="t('KANBAN.CARD.GO_TO_CONVERSATION')"
              @click.stop="goToBestConversation"
            >
              <span
                class="size-3.5"
                :class="
                  isNavigating
                    ? 'i-lucide-loader-2 animate-spin'
                    : 'i-lucide-message-circle'
                "
              />
              {{ t('KANBAN.CARD.GO_TO_CONVERSATION') }}
            </button>
          </div>
        </div>

        <!-- Dates -->
        <div
          v-if="displayContact.created_at || displayContact.last_activity_at"
          class="flex gap-6 text-xs border-t border-n-weak pt-4"
        >
          <div v-if="displayContact.created_at" class="flex flex-col gap-0.5">
            <span class="text-n-slate-10">
              {{ t('KANBAN.MODAL.CREATED_AT') }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ dynamicTime(displayContact.created_at) }}
            </span>
          </div>
          <div
            v-if="displayContact.last_activity_at"
            class="flex flex-col gap-0.5"
          >
            <span class="text-n-slate-10">
              {{ t('KANBAN.MODAL.LAST_ACTIVITY') }}
            </span>
            <span class="font-medium text-n-slate-12">
              {{ dynamicTime(displayContact.last_activity_at) }}
            </span>
          </div>
        </div>

        <!-- Custom attributes -->
        <div class="flex flex-col gap-2.5">
          <h4
            class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
          >
            {{ t('KANBAN.MODAL.CUSTOM_ATTRIBUTES_TITLE') }}
          </h4>
          <p
            v-if="customAttributesList.length === 0"
            class="text-xs text-n-slate-10"
          >
            {{ t('KANBAN.MODAL.NO_CUSTOM_ATTRIBUTES') }}
          </p>
          <div v-else class="grid grid-cols-2 gap-2">
            <div
              v-for="attr in customAttributesList"
              :key="attr.label"
              class="flex flex-col gap-0.5 p-2.5 rounded-lg bg-n-alpha-1 border border-n-weak"
            >
              <span class="text-xs text-n-slate-10 truncate">
                {{ attr.label }}
              </span>
              <span class="text-sm font-medium text-n-slate-12 truncate">
                {{ attr.value }}
              </span>
            </div>
          </div>
        </div>

        <!-- Conversations -->
        <div class="flex flex-col gap-2.5">
          <h4
            class="text-xs font-semibold text-n-slate-10 uppercase tracking-wide"
          >
            {{ t('KANBAN.MODAL.CONVERSATIONS_TITLE') }}
          </h4>
          <p
            v-if="!isLoading && conversations.length === 0"
            class="text-xs text-n-slate-10"
          >
            {{ t('KANBAN.MODAL.NO_CONVERSATIONS') }}
          </p>
          <div v-else class="flex flex-col gap-1.5">
            <button
              v-for="conv in conversations.slice(0, 5)"
              :key="conv.id"
              class="flex items-center gap-2.5 p-2.5 rounded-lg border border-n-weak hover:bg-n-alpha-1 text-left transition-colors w-full"
              @click.stop="navigateToConversation(conv)"
            >
              <span
                class="text-xs px-1.5 py-0.5 rounded font-medium flex-shrink-0"
                :class="statusClass(conv.status)"
              >
                {{ statusLabel(conv.status) }}
              </span>
              <span class="text-xs text-n-slate-11 flex-1 min-w-0 truncate">
                #{{ conv.id
                }}<span
                  v-if="conv.meta?.assignee?.name"
                  class="text-n-slate-10"
                >
                  · {{ conv.meta.assignee.name }}</span
                >
              </span>
              <span class="text-xs text-n-slate-10 flex-shrink-0">
                {{ dynamicTime(conv.last_activity_at) }}
              </span>
            </button>
            <button
              v-if="conversations.length > 5"
              class="text-xs text-n-brand hover:underline text-left py-1"
              @click.stop="goToContact"
            >
              {{ t('KANBAN.MODAL.VIEW_ALL_CONVERSATIONS') }}
            </button>
          </div>
        </div>
      </template>
    </div>
  </Dialog>
</template>
