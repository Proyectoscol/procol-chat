<script setup>
defineProps({
  inboxes: {
    type: Array,
    required: true,
  },
  label: {
    type: String,
    required: true,
  },
  hint: {
    type: String,
    default: '',
  },
});

const selectedInboxIds = defineModel({ type: Array, required: true });
</script>

<template>
  <div class="w-full mb-4">
    <span class="text-sm font-medium text-n-slate-12">{{ label }}</span>
    <p v-if="hint" class="text-xs text-n-slate-11 mb-2">{{ hint }}</p>
    <div class="flex flex-col gap-1.5">
      <label
        v-for="inbox in inboxes"
        :key="inbox.id"
        class="flex items-center gap-2 cursor-pointer"
      >
        <input v-model="selectedInboxIds" type="checkbox" :value="inbox.id" />
        <span class="text-sm text-n-slate-11">{{ inbox.name }}</span>
      </label>
    </div>
  </div>
</template>
