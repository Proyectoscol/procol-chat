<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  DAY_START_HOUR,
  DAY_END_HOUR,
  TOTAL_MINUTES,
  layoutDayEvents,
  isSameDay,
  dateFromDayOffset,
} from '../helpers/dayGridLayout';

const props = defineProps({
  modelValue: { type: Date, required: true },
  resources: { type: Array, required: true },
  events: { type: Array, required: true },
});
const emit = defineEmits(['update:modelValue', 'slotClick', 'eventClick']);

const { t } = useI18n();

const GRID_HEIGHT_PX = 900;
const HOUR_PX = GRID_HEIGHT_PX / (DAY_END_HOUR - DAY_START_HOUR);

const hours = Array.from(
  { length: DAY_END_HOUR - DAY_START_HOUR + 1 },
  (_, i) => DAY_START_HOUR + i
);

const titleLabel = computed(() =>
  new Intl.DateTimeFormat('es', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  }).format(props.modelValue)
);

const goPrev = () => {
  const next = new Date(props.modelValue);
  next.setDate(next.getDate() - 1);
  emit('update:modelValue', next);
};
const goNext = () => {
  const next = new Date(props.modelValue);
  next.setDate(next.getDate() + 1);
  emit('update:modelValue', next);
};
const goToday = () => emit('update:modelValue', new Date());

const eventsForResource = resourceId => {
  const dayEvents = props.events.filter(
    event =>
      String(event.resourceId) === String(resourceId) &&
      isSameDay(new Date(event.start), props.modelValue)
  );
  return layoutDayEvents(dayEvents);
};

const now = ref(new Date());
let nowTimer = null;
onMounted(() => {
  nowTimer = setInterval(() => {
    now.value = new Date();
  }, 60000);
});
onUnmounted(() => clearInterval(nowTimer));

const showNowIndicator = computed(() => isSameDay(now.value, props.modelValue));
const nowTopPct = computed(() => {
  const minutes =
    (now.value.getHours() - DAY_START_HOUR) * 60 + now.value.getMinutes();
  return (Math.min(Math.max(minutes, 0), TOTAL_MINUTES) / TOTAL_MINUTES) * 100;
});

const onColumnClick = (event, resourceId) => {
  if (event.target.closest('[data-appointment-card]')) return;
  const rect = event.currentTarget.getBoundingClientRect();
  const offsetY = event.clientY - rect.top;
  const offsetMinutes = (offsetY / GRID_HEIGHT_PX) * TOTAL_MINUTES;
  const date = dateFromDayOffset(props.modelValue, offsetMinutes);
  emit('slotClick', { date, resourceId: Number(resourceId) });
};

const hourLabel = hour => `${String(hour).padStart(2, '0')}:00`;
const timeLabel = date =>
  new Intl.DateTimeFormat('es', { hour: '2-digit', minute: '2-digit' }).format(
    date
  );
</script>

<template>
  <div class="flex flex-col gap-3">
    <div class="flex items-center gap-2">
      <Button
        size="sm"
        slate
        faded
        icon="i-lucide-chevron-left"
        @click="goPrev"
      />
      <Button size="sm" slate faded @click="goToday">
        {{ t('CALENDARIO.CALENDAR.DAY_VIEW.TODAY') }}
      </Button>
      <Button
        size="sm"
        slate
        faded
        icon="i-lucide-chevron-right"
        @click="goNext"
      />
      <h3 class="text-sm font-medium text-n-slate-12 capitalize ml-2">
        {{ titleLabel }}
      </h3>
    </div>

    <div class="border border-n-weak rounded-lg overflow-x-auto">
      <div
        class="grid"
        :style="{
          gridTemplateColumns: `64px repeat(${resources.length}, minmax(140px, 1fr))`,
        }"
      >
        <div class="border-b border-n-weak" />
        <div
          v-for="resource in resources"
          :key="resource.id"
          class="border-b border-l border-n-weak px-2 py-2 text-sm font-medium text-n-slate-12 truncate"
        >
          {{ resource.title }}
        </div>

        <div class="relative" :style="{ height: `${GRID_HEIGHT_PX}px` }">
          <div
            v-for="hour in hours"
            :key="hour"
            class="absolute left-0 right-0 text-[11px] text-n-slate-10 -translate-y-1/2 text-right pr-1"
            :style="{ top: `${(hour - DAY_START_HOUR) * HOUR_PX}px` }"
          >
            {{ hourLabel(hour) }}
          </div>
        </div>

        <div
          v-for="resource in resources"
          :key="`col-${resource.id}`"
          class="relative border-l border-n-weak"
          :style="{ height: `${GRID_HEIGHT_PX}px` }"
          @click="onColumnClick($event, resource.id)"
        >
          <div
            v-for="hour in hours"
            :key="hour"
            class="absolute left-0 right-0 border-t border-n-weak"
            :style="{ top: `${(hour - DAY_START_HOUR) * HOUR_PX}px` }"
          />

          <div
            v-if="showNowIndicator"
            class="absolute left-0 right-0 border-t-2 border-n-ruby-9 z-10 pointer-events-none"
            :style="{ top: `${nowTopPct}%` }"
          />

          <div
            v-for="ev in eventsForResource(resource.id)"
            :key="ev.id"
            data-appointment-card
            class="absolute rounded-lg shadow-sm overflow-hidden cursor-pointer px-1 py-0.5"
            :style="{
              top: `${ev.topPct}%`,
              height: `${ev.heightPct}%`,
              left: `${ev.leftPct}%`,
              width: `calc(${ev.widthPct}% - 2px)`,
              backgroundColor: ev.backgroundColor,
              color: ev.textColor,
              borderLeft: `3px solid ${ev.borderColor}`,
            }"
            @click.stop="$emit('eventClick', ev.id)"
          >
            <div class="flex items-start gap-1 w-full overflow-hidden">
              <span
                class="mt-1 size-2 shrink-0 rounded-full"
                :style="{ backgroundColor: ev.extendedProps.serviceColor }"
              />
              <div class="flex flex-col min-w-0 leading-tight">
                <p class="text-xs font-medium truncate">
                  {{ ev.extendedProps.contactName }}
                </p>
                <p class="text-[11px] opacity-80 truncate">
                  {{
                    `${timeLabel(new Date(ev.start))} · ${ev.extendedProps.serviceName}`
                  }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
