<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { VOICE_CALL_DIRECTION } from 'dashboard/components-next/message/constants';
import { VOICE_CALL_PROVIDERS } from 'dashboard/helper/inbox';
import {
  useJsSipSession,
  setSipCallMuted,
} from 'dashboard/composables/useJsSipSession';
import { useCallsStore } from 'dashboard/stores/calls';
import { useCallActions } from 'dashboard/composables/useCallSession';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Popover from 'dashboard/components-next/popover/Popover.vue';

const { t } = useI18n();

const { isRegistered, isReconnecting, callFailureReason, startCall, endCall } =
  useJsSipSession();
const callsStore = useCallsStore();
// Lighter consumer: reads active-call state + actions without mounting the
// global window/Timer listeners that FloatingCallWidget already owns.
const { activeCall, formattedCallDuration } = useCallActions();

// --- Section 1: SIP status badge (icon + text + color, not color alone) -------
const sipStatus = computed(() => {
  if (isReconnecting.value) {
    return {
      label: t('VOICE_TELEPHONY.PANEL.STATUS.RECONNECTING'),
      icon: 'i-ph-arrows-clockwise-bold',
      color: 'text-n-amber-9',
    };
  }
  if (isRegistered.value) {
    return {
      label: t('VOICE_TELEPHONY.PANEL.STATUS.AVAILABLE'),
      icon: 'i-ph-phone-bold',
      color: 'text-n-teal-9',
    };
  }
  return {
    label: t('VOICE_TELEPHONY.PANEL.STATUS.DISCONNECTED'),
    icon: 'i-ph-phone-slash-bold',
    color: 'text-n-ruby-9',
  };
});

// Bug 3: mapear causa JsSIP → texto legible (se muestra 5 s y se auto-limpia).
const FAILURE_CAUSE_MAP = {
  Rejected: 'VOICE_TELEPHONY.CALL_FAILURE.REJECTED',
  Busy: 'VOICE_TELEPHONY.CALL_FAILURE.BUSY',
  Unavailable: 'VOICE_TELEPHONY.CALL_FAILURE.UNAVAILABLE',
  'No Answer': 'VOICE_TELEPHONY.CALL_FAILURE.NO_ANSWER',
  Canceled: 'VOICE_TELEPHONY.CALL_FAILURE.CANCELED',
  'Invalid Number': 'VOICE_TELEPHONY.CALL_FAILURE.INVALID_NUMBER',
  'Mic Denied': 'VOICE_TELEPHONY.CALL_FAILURE.MIC_DENIED',
};
const callFailureLabel = computed(() => {
  if (!callFailureReason.value) return '';
  const key = FAILURE_CAUSE_MAP[callFailureReason.value];
  return key ? t(key) : t('VOICE_TELEPHONY.CALL_FAILURE.UNKNOWN');
});

// --- Section 2: active call ---------------------------------------------------
const hasAsteriskCall = computed(
  () => activeCall.value?.provider === VOICE_CALL_PROVIDERS.ASTERISK
);
const isMuted = ref(false);
const isHeld = ref(false);

// Mute and Hold compose over the single mic track: muted if either is on. True
// SIP hold (re-INVITE sendonly) is phase 2; v1 hold mutes the local mic.
const applyMicState = () => setSipCallMuted(isMuted.value || isHeld.value);
const toggleMute = () => {
  isMuted.value = !isMuted.value;
  applyMicState();
};
const toggleHold = () => {
  isHeld.value = !isHeld.value;
  applyMicState();
};

const hangUp = () => {
  const call = activeCall.value;
  if (!call) return;
  endCall({
    callSid: call.callSid,
    conversationId: call.conversationId,
    inboxId: call.inboxId,
  });
  isMuted.value = false;
  isHeld.value = false;
};

// Same-Team agents with sip_active_contacts > 0. Populated by the backend list
// endpoint (pending); empty → the popover shows its empty state.
const availableAgents = ref([]);
const onTransfer = (agent, hide) => {
  hide();
  // Backend pendiente: callsStore.blindTransfer(activeCall.callSid, agent.sipExtension).
  callsStore.blindTransfer?.(activeCall.value?.callSid, agent.sipExtension);
};

// --- Shared outbound helper (dialpad, directory, call-back) --------------------
const placeOutboundCall = async number => {
  if (!number) return;
  const session = await startCall(number);
  if (!session) return;
  callsStore.addCall({
    callSid: session.id,
    phoneNumber: number,
    conversationId: null,
    inboxId: null,
    callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
    provider: VOICE_CALL_PROVIDERS.ASTERISK,
  });
};

// --- Tabs: Dial | Directory | Recents -----------------------------------------
const activeTab = ref('dial');
const tabs = computed(() => [
  { key: 'dial', label: t('VOICE_TELEPHONY.PANEL.TABS.DIAL') },
  { key: 'directory', label: t('VOICE_TELEPHONY.PANEL.TABS.DIRECTORY') },
  { key: 'recents', label: t('VOICE_TELEPHONY.PANEL.TABS.RECENTS') },
]);

// --- Section 3: dialpad DTMF --------------------------------------------------
const dialNumber = ref('');
const dialpadKeys = [
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  '*',
  '0',
  '#',
];
const appendDigit = key => {
  dialNumber.value += key;
};
const backspace = () => {
  dialNumber.value = dialNumber.value.slice(0, -1);
};
const onDial = async () => {
  await placeOutboundCall(dialNumber.value);
  dialNumber.value = '';
};

// --- Section 4: directory of contacts assigned to the agent -------------------
// Data source pending (backend getter/endpoint); empty → empty state.
const assignedContacts = ref([]);

// --- Section 5: call history --------------------------------------------------
// Data source pending (Call history endpoint); empty → empty state.
const callHistory = ref([]);
const historyMeta = {
  incoming: { icon: 'i-ph-phone-incoming-bold', color: 'text-n-teal-9' },
  outgoing: { icon: 'i-ph-phone-outgoing-bold', color: 'text-n-slate-10' },
  missed: { icon: 'i-ph-phone-x-bold', color: 'text-n-ruby-9' },
};
const historyIcon = direction =>
  (historyMeta[direction] || historyMeta.outgoing).icon;
const historyColor = direction =>
  (historyMeta[direction] || historyMeta.outgoing).color;
const formatRelative = ts => (ts ? new Date(ts).toLocaleString() : '');
</script>

<template>
  <div
    class="flex flex-col w-full h-full bg-n-solid-1 border-l border-n-strong"
  >
    <!-- Section 1: SIP status badge -->
    <div class="flex items-center gap-2 px-4 py-3 border-b border-n-weak">
      <Icon :icon="sipStatus.icon" :class="sipStatus.color" class="size-4" />
      <span class="text-sm font-medium" :class="sipStatus.color">
        {{ sipStatus.label }}
      </span>
    </div>
    <!-- Bug 3: failure reason badge — visible 5 s, luego desaparece solo -->
    <Transition
      enter-active-class="transition-opacity duration-200"
      leave-active-class="transition-opacity duration-300"
      enter-from-class="opacity-0"
      leave-to-class="opacity-0"
    >
      <div
        v-if="callFailureLabel"
        class="flex items-center gap-1.5 px-4 py-2 bg-n-ruby-2 border-b border-n-ruby-4"
      >
        <Icon
          icon="i-ph-phone-x-bold"
          class="size-3.5 text-n-ruby-9 shrink-0"
        />
        <span class="text-xs text-n-ruby-9 font-medium">{{
          callFailureLabel
        }}</span>
      </div>
    </Transition>

    <!-- Section 2: active call -->
    <div
      v-if="hasAsteriskCall"
      class="flex flex-col gap-3 px-4 py-4 border-b border-n-weak bg-n-solid-2"
    >
      <div class="flex items-center gap-3">
        <Avatar
          :name="activeCall.contactName || activeCall.phoneNumber"
          :size="36"
        />
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium text-n-slate-12 truncate mb-0">
            {{ activeCall.contactName || activeCall.phoneNumber }}
          </p>
          <p class="text-xs text-n-slate-11 truncate mb-0">
            {{ activeCall.phoneNumber }}
          </p>
        </div>
        <span class="text-sm font-medium text-n-slate-11 tabular-nums">
          {{ formattedCallDuration }}
        </span>
      </div>

      <div class="flex items-center gap-2">
        <NextButton
          v-tooltip.top="
            isMuted
              ? $t('VOICE_TELEPHONY.PANEL.ACTIVE_CALL.UNMUTE')
              : $t('VOICE_TELEPHONY.PANEL.ACTIVE_CALL.MUTE')
          "
          :icon="
            isMuted ? 'i-ph-microphone-slash-bold' : 'i-ph-microphone-bold'
          "
          :variant="isMuted ? 'solid' : 'faded'"
          :color="isMuted ? 'amber' : 'teal'"
          class="!rounded-full"
          @click="toggleMute"
        />
        <NextButton
          v-tooltip.top="
            isHeld
              ? $t('VOICE_TELEPHONY.CALL_CONTROLS.RESUME')
              : $t('VOICE_TELEPHONY.CALL_CONTROLS.HOLD')
          "
          :icon="isHeld ? 'i-ph-play-bold' : 'i-ph-pause-bold'"
          :variant="isHeld ? 'solid' : 'faded'"
          :color="isHeld ? 'amber' : 'teal'"
          class="!rounded-full"
          @click="toggleHold"
        />
        <Popover align="start">
          <NextButton
            v-tooltip.top="$t('VOICE_TELEPHONY.CALL_CONTROLS.TRANSFER')"
            icon="i-ph-arrows-left-right-bold"
            variant="faded"
            color="teal"
            class="!rounded-full"
          />
          <template #content="{ hide }">
            <div class="flex flex-col gap-1 p-2 w-56">
              <p class="px-2 py-1 text-xs font-medium text-n-slate-11">
                {{ $t('VOICE_TELEPHONY.TRANSFER.TITLE') }}
              </p>
              <button
                v-for="agent in availableAgents"
                :key="agent.id"
                type="button"
                class="flex items-center justify-between w-full px-2 py-1.5 text-left rounded-lg hover:bg-n-alpha-2"
                @click="onTransfer(agent, hide)"
              >
                <span class="text-sm text-n-slate-12 truncate">
                  {{ agent.name }}
                </span>
                <span class="text-xs text-n-slate-10 tabular-nums">
                  {{ agent.sipExtension }}
                </span>
              </button>
              <p
                v-if="!availableAgents.length"
                class="px-2 py-1.5 text-sm text-n-slate-10"
              >
                {{ $t('VOICE_TELEPHONY.TRANSFER.EMPTY') }}
              </p>
            </div>
          </template>
        </Popover>
        <NextButton
          v-tooltip.top="$t('VOICE_TELEPHONY.PANEL.ACTIVE_CALL.HANG_UP')"
          icon="i-ph-phone-x-bold"
          ruby
          class="!rounded-full rotate-[134deg] ml-auto"
          @click="hangUp"
        />
      </div>
    </div>

    <!-- Tabs -->
    <div class="flex items-center gap-1 px-2 py-2 border-b border-n-weak">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        class="flex-1 px-3 py-1.5 text-sm font-medium rounded-lg"
        :class="
          activeTab === tab.key
            ? 'bg-n-alpha-2 text-n-slate-12'
            : 'text-n-slate-11 hover:bg-n-alpha-1'
        "
        @click="activeTab = tab.key"
      >
        {{ tab.label }}
      </button>
    </div>

    <div class="flex-1 min-h-0 overflow-y-auto">
      <!-- Section 3: dialpad -->
      <div v-if="activeTab === 'dial'" class="flex flex-col gap-3 p-4">
        <input
          v-model="dialNumber"
          type="text"
          inputmode="tel"
          :placeholder="$t('VOICE_TELEPHONY.PANEL.DIAL.PLACEHOLDER')"
          class="w-full px-3 py-2 text-center text-lg tabular-nums bg-n-solid-2 border border-n-weak rounded-lg text-n-slate-12 focus:outline-none focus:border-n-teal-7"
        />
        <div class="grid grid-cols-3 gap-2">
          <button
            v-for="key in dialpadKeys"
            :key="key"
            type="button"
            class="py-3 text-lg font-medium tabular-nums rounded-lg bg-n-solid-2 text-n-slate-12 hover:bg-n-alpha-2"
            @click="appendDigit(key)"
          >
            {{ key }}
          </button>
        </div>
        <div class="flex items-center gap-2">
          <NextButton
            :label="$t('VOICE_TELEPHONY.PANEL.DIAL.CALL')"
            icon="i-ph-phone-bold"
            teal
            :disabled="!dialNumber"
            class="flex-1"
            @click="onDial"
          />
          <NextButton
            icon="i-ph-backspace-bold"
            slate
            faded
            :disabled="!dialNumber"
            @click="backspace"
          />
        </div>
      </div>

      <!-- Section 4: directory -->
      <div v-else-if="activeTab === 'directory'" class="flex flex-col">
        <button
          v-for="contact in assignedContacts"
          :key="contact.id"
          type="button"
          class="flex items-center gap-3 px-4 py-2.5 text-left hover:bg-n-alpha-1"
          @click="placeOutboundCall(contact.phoneNumber)"
        >
          <Avatar :name="contact.name" :size="28" />
          <div class="flex-1 min-w-0">
            <p class="text-sm text-n-slate-12 truncate mb-0">
              {{ contact.name }}
            </p>
            <p class="text-xs text-n-slate-11 truncate mb-0">
              {{ contact.phoneNumber }}
            </p>
          </div>
          <Icon icon="i-ph-phone-bold" class="size-4 text-n-teal-9" />
        </button>
        <p
          v-if="!assignedContacts.length"
          class="px-4 py-8 text-sm text-center text-n-slate-10"
        >
          {{ $t('VOICE_TELEPHONY.PANEL.DIRECTORY.EMPTY') }}
        </p>
      </div>

      <!-- Section 5: call history -->
      <div v-else class="flex flex-col">
        <div
          v-for="call in callHistory"
          :key="call.id"
          class="flex items-center gap-3 px-4 py-2.5 hover:bg-n-alpha-1"
        >
          <Icon
            :icon="historyIcon(call.direction)"
            :class="historyColor(call.direction)"
            class="size-4 shrink-0"
          />
          <div class="flex-1 min-w-0">
            <p class="text-sm text-n-slate-12 truncate mb-0">
              {{ call.name || call.phoneNumber }}
            </p>
            <p class="text-xs text-n-slate-11 truncate mb-0">
              {{ formatRelative(call.createdAt) }}
            </p>
          </div>
          <NextButton
            v-if="call.direction === 'missed'"
            v-tooltip.top="$t('VOICE_TELEPHONY.PANEL.RECENTS.CALL_BACK')"
            icon="i-ph-arrow-counter-clockwise-bold"
            teal
            faded
            xs
            class="!rounded-full"
            @click="placeOutboundCall(call.phoneNumber)"
          />
        </div>
        <p
          v-if="!callHistory.length"
          class="px-4 py-8 text-sm text-center text-n-slate-10"
        >
          {{ $t('VOICE_TELEPHONY.PANEL.RECENTS.EMPTY') }}
        </p>
      </div>
    </div>
  </div>
</template>
