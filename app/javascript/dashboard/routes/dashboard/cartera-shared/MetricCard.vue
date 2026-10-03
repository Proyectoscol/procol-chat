<script setup>
defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], default: 0 },
  hint: { type: String, default: '' },
  loading: { type: Boolean, default: false },
});
</script>

<template>
  <div
    class="flex flex-col gap-3 p-5 rounded-xl border border-n-weak bg-n-solid-1"
  >
    <div class="flex items-center gap-1.5">
      <span class="text-sm font-medium text-n-slate-11">{{ label }}</span>
      <span
        v-if="hint"
        v-tooltip="hint"
        class="i-lucide-info size-3.5 text-n-slate-10"
      />
    </div>
    <div v-if="loading" class="w-24 rounded h-9 bg-n-slate-3 animate-pulse" />
    <span
      v-else
      class="text-2xl font-semibold tracking-tight tabular-nums text-n-slate-12"
    >
      {{ value }}
    </span>
  </div>
</template>
