<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useCamelCase } from 'dashboard/composables/useTransformKeys';
import AuditoriaDailyJobsAPI from 'dashboard/api/auditoriaDailyJobs';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  kind: { type: String, required: true },
});
// Mismo link para los 3 kinds -- confirmar con el usuario si OpenAI cambio
// la ruta exacta de su panel de Organization Usage.
const OPENAI_USAGE_URL =
  'https://platform.openai.com/settings/organization/usage';
const POLL_INTERVAL_MS = 3000;

const { t } = useI18n();
const progress = ref(null);
// Un "completado" viejo queda en Redis hasta 6h (a proposito, para que
// sobreviva un refresco de pagina mientras el admin vuelve a revisar) --
// pero una vez ya lo vio, no debe seguir ocupando espacio en cada visita
// futura a esta pantalla dentro de esa ventana. Se descarta manualmente,
// y se reactiva solo si arranca una corrida NUEVA de verdad.
const dismissed = ref(false);
let pollTimer = null;

// Silencioso a proposito -- un poll fallido (ej. blip de red) no debe
// interrumpir al admin con una alerta; se reintenta solo en el siguiente
// tick, 3 segundos despues.
const fetchProgress = async () => {
  try {
    const { data } = await AuditoriaDailyJobsAPI.getProgress(props.kind);
    const next = useCamelCase(data, { deep: true });
    if (next?.status === 'running' && progress.value?.status !== 'running') {
      dismissed.value = false;
    }
    progress.value = next;
  } catch {
    // intencional: ver comentario arriba
  }
};

onMounted(() => {
  fetchProgress();
  pollTimer = setInterval(fetchProgress, POLL_INTERVAL_MS);
});
onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer);
});

const isVisible = computed(
  () => progress.value && progress.value.status !== 'idle' && !dismissed.value
);
const dismiss = () => {
  dismissed.value = true;
};
const isRunning = computed(() => progress.value?.status === 'running');
const percent = computed(() => {
  if (!progress.value?.total) return 0;
  const done = (progress.value.processed || 0) + (progress.value.errored || 0);
  return Math.min(100, Math.round((done / progress.value.total) * 100));
});
</script>

<template>
  <div
    v-if="isVisible"
    class="flex flex-col gap-2 p-4 rounded-xl outline outline-1 outline-n-weak bg-n-solid-2"
  >
    <div class="flex items-center justify-between">
      <span class="text-sm font-medium text-n-slate-12">
        {{
          isRunning
            ? t('AUDITORIA_AI_USAGE.PROGRESS_RUNNING')
            : t('AUDITORIA_AI_USAGE.PROGRESS_COMPLETED')
        }}
      </span>
      <div class="flex items-center gap-2">
        <span class="text-xs text-n-slate-10">{{ percent }}%</span>
        <button
          v-if="!isRunning"
          type="button"
          class="text-n-slate-10 hover:text-n-slate-12"
          :aria-label="t('AUDITORIA_AI_USAGE.PROGRESS_DISMISS')"
          @click="dismiss"
        >
          <Icon icon="i-lucide-x" class="size-3.5" />
        </button>
      </div>
    </div>
    <div class="w-full h-2 rounded-full bg-n-alpha-2 overflow-hidden">
      <div
        class="h-full bg-n-brand transition-all"
        :style="{ width: `${percent}%` }"
      />
    </div>
    <p class="text-xs text-n-slate-11">
      {{
        t('AUDITORIA_AI_USAGE.PROGRESS_COUNTS', {
          processed: progress.processed,
          errored: progress.errored,
          total: progress.total,
        })
      }}
    </p>
    <p v-if="isRunning" class="text-xs text-n-slate-10">
      {{ t('AUDITORIA_AI_USAGE.PROGRESS_SAFE_TO_LEAVE') }}
    </p>
    <div
      v-if="progress.spendLimited"
      class="flex flex-col gap-1 p-3 rounded-lg bg-n-ruby-2 text-n-ruby-11 text-xs"
    >
      <span>{{ t('AUDITORIA_AI_USAGE.PROGRESS_SPEND_LIMITED') }}</span>
      <a
        :href="OPENAI_USAGE_URL"
        target="_blank"
        rel="noopener noreferrer"
        class="underline"
      >
        {{ t('AUDITORIA_AI_USAGE.PROGRESS_SPEND_LIMITED_LINK') }}
      </a>
    </div>
  </div>
</template>
