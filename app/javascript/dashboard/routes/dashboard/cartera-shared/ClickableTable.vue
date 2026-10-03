<!-- Mismo markup/clases que dashboard/components/table/Table.vue, pero con
la fila clickeable - Table.vue no expone ese hook. El patron de "tabla a
medida con las mismas clases + fila clickeable" ya existe en este repo en
CsatTable.vue; esto lo generaliza como componente compartido en vez de
duplicar el fork en Clientes y en Facturas. -->
<script setup>
import { FlexRender } from '@tanstack/vue-table';

const props = defineProps({
  table: {
    type: Object,
    required: true,
  },
  clickable: {
    type: Boolean,
    default: true,
  },
});

const emit = defineEmits(['rowClick']);

const onRowClick = row => {
  if (props.clickable) emit('rowClick', row.original);
};
</script>

<template>
  <table>
    <thead class="sticky top-0 z-10 bg-n-slate-1">
      <tr v-for="headerGroup in table.getHeaderGroups()" :key="headerGroup.id">
        <th
          v-for="header in headerGroup.headers"
          :key="header.id"
          :style="{ width: `${header.getSize()}px` }"
          class="text-left py-3 px-5 font-medium text-sm text-n-slate-12"
        >
          <div
            v-if="!header.isPlaceholder"
            class="flex place-items-center gap-1"
          >
            <FlexRender
              :render="header.column.columnDef.header"
              :props="header.getContext()"
            />
          </div>
        </th>
      </tr>
    </thead>
    <tbody class="divide-y divide-n-slate-2">
      <tr
        v-for="row in table.getRowModel().rows"
        :key="row.id"
        class="transition-colors"
        :class="
          clickable
            ? 'cursor-pointer hover:bg-n-slate-2 dark:hover:bg-n-solid-3'
            : ''
        "
        @click="onRowClick(row)"
      >
        <td
          v-for="cell in row.getVisibleCells()"
          :key="cell.id"
          class="py-4 px-5"
        >
          <FlexRender
            :render="cell.column.columnDef.cell"
            :props="cell.getContext()"
          />
        </td>
      </tr>
    </tbody>
  </table>
</template>
