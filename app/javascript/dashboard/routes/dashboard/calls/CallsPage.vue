<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
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

const {
  isRegistered,
  isReconnecting,
  callFailureReason,
  startCall,
  rejectCall,
  register,
  unregister,
} = useJsSipSession();
const callsStore = useCallsStore();
const { activeCall, formattedCallDuration, endCall } = useCallActions();

// --- SIP status badge ---------------------------------------------------
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

// Map JsSIP cause → i18n key. 'SIP Failure Code' is JsSIP's catch-all for
// any 4xx/5xx not specifically handled — check console for the actual code.
const FAILURE_CAUSE_MAP = {
  Rejected: 'VOICE_TELEPHONY.CALL_FAILURE.REJECTED',
  Busy: 'VOICE_TELEPHONY.CALL_FAILURE.BUSY',
  Unavailable: 'VOICE_TELEPHONY.CALL_FAILURE.UNAVAILABLE',
  'No Answer': 'VOICE_TELEPHONY.CALL_FAILURE.NO_ANSWER',
  Canceled: 'VOICE_TELEPHONY.CALL_FAILURE.CANCELED',
  'Invalid Number': 'VOICE_TELEPHONY.CALL_FAILURE.INVALID_NUMBER',
  'Mic Denied': 'VOICE_TELEPHONY.CALL_FAILURE.MIC_DENIED',
  'SIP Failure Code': 'VOICE_TELEPHONY.CALL_FAILURE.SIP_ERROR',
};

// --- Dialing / ringing state (outbound before answer) -------------------
const isDialingOut = ref(false);
const dialingNumber = ref('');
let userCanceled = false;

// Watch call failure and show alert (except user-initiated cancel)
watch(
  () => callFailureReason.value,
  reason => {
    if (!reason) return;
    isDialingOut.value = false;
    dialingNumber.value = '';
    if (!userCanceled) {
      const key = FAILURE_CAUSE_MAP[reason];
      useAlert(key ? t(key) : t('VOICE_TELEPHONY.CALL_FAILURE.UNKNOWN'));
    }
    userCanceled = false;
  }
);

// When outbound call is confirmed, clear dialing state
watch(
  () => activeCall.value,
  call => {
    if (call?.provider === VOICE_CALL_PROVIDERS.ASTERISK) {
      isDialingOut.value = false;
      dialingNumber.value = '';
    }
  }
);

// --- Active confirmed call ---------------------------------------------
const hasAsteriskCall = computed(
  () => activeCall.value?.provider === VOICE_CALL_PROVIDERS.ASTERISK
);

// --- Manual SIP reconnect (fixes stale WebSocket contact in Asterisk) ---
// unregister→register cycle opens a fresh WebSocket and forces Asterisk to
// update the contact binding, fixing Q.850:34 on incoming calls.
const isReconnectingManual = ref(false);
const reconnect = async () => {
  if (isReconnectingManual.value || hasAsteriskCall.value || isDialingOut.value)
    return;
  isReconnectingManual.value = true;
  unregister();
  await new Promise(resolve => {
    setTimeout(resolve, 800);
  });
  await register();
  isReconnectingManual.value = false;
};

const isMuted = ref(false);
const isHeld = ref(false);

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

const availableAgents = ref([]);
const onTransfer = (agent, hide) => {
  hide();
  callsStore.blindTransfer?.(activeCall.value?.callSid, agent.sipExtension);
};

// --- Cancel outbound call before answer --------------------------------
const cancelDial = () => {
  userCanceled = true;
  isDialingOut.value = false;
  dialingNumber.value = '';
  rejectCall();
};

// --- Outbound dialing --------------------------------------------------
const placeOutboundCall = async number => {
  if (!number) return;
  const session = await startCall(number);
  if (!session) return; // failure already set via callFailureReason
  isDialingOut.value = true;
  dialingNumber.value = number;
  callsStore.addCall({
    callSid: session.id,
    phoneNumber: number,
    conversationId: null,
    inboxId: null,
    callDirection: VOICE_CALL_DIRECTION.OUTBOUND,
    provider: VOICE_CALL_PROVIDERS.ASTERISK,
  });
};

// --- Dialpad -----------------------------------------------------------
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
  const num = dialNumber.value;
  dialNumber.value = '';
  await placeOutboundCall(num);
};

// --- Directory and Recents (backend pending, placeholders) ------------
const assignedContacts = ref([]);
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
  <div class="flex flex-col h-full w-full">
    <!-- Page header — same pattern as Kanban -->
    <header
      class="flex items-center gap-3 px-6 py-3 border-b border-n-weak flex-shrink-0"
    >
      <span class="i-ph-phone-bold size-5 text-n-slate-11" />
      <h1 class="text-base font-semibold text-n-slate-12 flex-1">
        {{ t('SIDEBAR.CALLS') }}
      </h1>
      <!-- SIP status chip -->
      <div
        class="flex items-center gap-1.5 px-2.5 py-1 rounded-full border border-n-weak bg-n-background"
      >
        <Icon
          :icon="sipStatus.icon"
          :class="sipStatus.color"
          class="size-3.5"
        />
        <span class="text-xs font-medium" :class="sipStatus.color">
          {{ sipStatus.label }}
        </span>
      </div>
      <!-- Reconnect button — fixes stale WebSocket contact in Asterisk -->
      <button
        v-tooltip.bottom="$t('VOICE_TELEPHONY.PANEL.RECONNECT')"
        type="button"
        :disabled="isReconnectingManual || hasAsteriskCall || isDialingOut"
        class="flex items-center justify-center size-7 rounded-lg text-n-slate-11 hover:bg-n-alpha-2 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
        @click="reconnect"
      >
        <Icon
          icon="i-ph-arrows-clockwise-bold"
          class="size-4"
          :class="isReconnectingManual ? 'animate-spin' : ''"
        />
      </button>
    </header>

    <!-- 3-column body: [dial controls] [directory] [recents] -->
    <div class="flex flex-1 min-h-0 overflow-hidden">
      <!-- ── Col 1: Dial controls (480px, fixed) ────────────────────── -->
      <div
        class="w-80 shrink-0 border-r border-n-weak flex flex-col overflow-hidden"
      >
        <!-- STATE A: Outbound ringing (before answer) -->
        <div v-if="isDialingOut" class="flex flex-col gap-4 p-4">
          <div
            class="flex items-center gap-3 p-3 rounded-xl bg-n-solid-2 border border-n-weak"
          >
            <!-- Pulsing phone icon -->
            <div
              class="relative size-10 shrink-0 flex items-center justify-center"
            >
              <div
                class="absolute inset-0 rounded-full bg-n-teal-3 animate-ping opacity-60"
              />
              <div
                class="relative size-10 rounded-full bg-n-teal-2 flex items-center justify-center"
              >
                <Icon icon="i-ph-phone-bold" class="size-5 text-n-teal-9" />
              </div>
            </div>
            <div class="flex-1 min-w-0">
              <p
                class="text-sm font-semibold text-n-slate-12 tabular-nums truncate"
              >
                {{ dialingNumber }}
              </p>
              <p class="text-xs text-n-teal-9 font-medium">
                {{ $t('VOICE_TELEPHONY.PANEL.DIAL.CALLING') }}
              </p>
            </div>
          </div>
          <NextButton
            :label="$t('VOICE_TELEPHONY.PANEL.ACTIVE_CALL.HANG_UP')"
            icon="i-ph-phone-x-bold"
            ruby
            class="w-full"
            @click="cancelDial"
          />
        </div>

        <!-- STATE B: Active call (confirmed / answered) -->
        <div
          v-else-if="hasAsteriskCall"
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

        <!-- STATE C: Dialpad (idle) -->
        <div v-else class="flex flex-col gap-3 p-4 overflow-y-auto flex-1">
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
      </div>

      <!-- ── Col 2: Directory (vertical scrollable list) ───────────── -->
      <div
        class="flex-1 flex flex-col min-h-0 border-r border-n-weak overflow-hidden"
      >
        <div
          class="flex items-center gap-2 px-4 py-2.5 border-b border-n-weak bg-n-background flex-shrink-0"
        >
          <Icon
            icon="i-ph-address-book-bold"
            class="size-4 text-n-slate-11 shrink-0"
          />
          <h2
            class="text-xs font-semibold text-n-slate-11 uppercase tracking-wider flex-1"
          >
            {{ $t('VOICE_TELEPHONY.PANEL.TABS.DIRECTORY') }}
          </h2>
        </div>
        <div class="flex-1 overflow-y-auto">
          <button
            v-for="contact in assignedContacts"
            :key="contact.id"
            type="button"
            class="flex items-center gap-3 w-full px-4 py-2.5 text-left hover:bg-n-alpha-1 border-b border-n-weak/50 last:border-b-0"
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
            <Icon
              icon="i-ph-phone-bold"
              class="size-4 text-n-teal-9 shrink-0 opacity-0 group-hover:opacity-100"
            />
          </button>
          <div
            v-if="!assignedContacts.length"
            class="flex flex-col items-center justify-center gap-3 py-16 px-4"
          >
            <span class="i-ph-address-book size-10 text-n-slate-7" />
            <p class="text-sm text-center text-n-slate-10">
              {{ $t('VOICE_TELEPHONY.PANEL.DIRECTORY.EMPTY') }}
            </p>
          </div>
        </div>
      </div>

      <!-- ── Col 3: Recents (vertical scrollable list) ─────────────── -->
      <div class="flex-1 flex flex-col min-h-0 overflow-hidden">
        <div
          class="flex items-center gap-2 px-4 py-2.5 border-b border-n-weak bg-n-background flex-shrink-0"
        >
          <Icon
            icon="i-ph-clock-counter-clockwise-bold"
            class="size-4 text-n-slate-11 shrink-0"
          />
          <h2
            class="text-xs font-semibold text-n-slate-11 uppercase tracking-wider flex-1"
          >
            {{ $t('VOICE_TELEPHONY.PANEL.TABS.RECENTS') }}
          </h2>
        </div>
        <div class="flex-1 overflow-y-auto">
          <div
            v-for="call in callHistory"
            :key="call.id"
            class="flex items-center gap-3 px-4 py-2.5 hover:bg-n-alpha-1 border-b border-n-weak/50 last:border-b-0"
          >
            <div
              class="size-8 rounded-full flex items-center justify-center shrink-0"
              :class="
                call.direction === 'missed'
                  ? 'bg-n-ruby-2'
                  : call.direction === 'incoming'
                    ? 'bg-n-teal-2'
                    : 'bg-n-alpha-2'
              "
            >
              <Icon
                :icon="historyIcon(call.direction)"
                :class="historyColor(call.direction)"
                class="size-4"
              />
            </div>
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
              class="!rounded-full shrink-0"
              @click="placeOutboundCall(call.phoneNumber)"
            />
          </div>
          <div
            v-if="!callHistory.length"
            class="flex flex-col items-center justify-center gap-3 py-16 px-4"
          >
            <span class="i-ph-clock-counter-clockwise size-10 text-n-slate-7" />
            <p class="text-sm text-center text-n-slate-10">
              {{ $t('VOICE_TELEPHONY.PANEL.RECENTS.EMPTY') }}
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
