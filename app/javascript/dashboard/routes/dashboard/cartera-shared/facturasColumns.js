import { h } from 'vue';
import { createColumnHelper } from '@tanstack/vue-table';
import { formatearCop, formatearFecha } from './format';

const spanCell = (value, className = 'text-body-main text-n-slate-12') =>
  h('span', { class: className }, value);

const columnHelper = createColumnHelper();

// Compartido entre FacturasTable.vue (listas embebidas, ej. en la ficha de
// cliente) y facturas/Index.vue (listado completo paginado) para no
// duplicar las mismas 8 columnas dos veces.
export const buildFacturasColumns = (t, hideClienteColumn = false) =>
  [
    columnHelper.accessor('numero', {
      header: t('CARTERA.FACTURAS.HEADERS.NUMERO'),
      size: 150,
      cell: cellProps =>
        spanCell(
          cellProps.getValue(),
          'text-body-main text-n-slate-12 whitespace-nowrap'
        ),
    }),
    !hideClienteColumn &&
      columnHelper.accessor('nombre_cliente', {
        header: t('CARTERA.FACTURAS.HEADERS.CLIENTE'),
        size: 180,
        cell: cellProps =>
          spanCell(
            cellProps.getValue(),
            'text-body-main text-n-slate-12 truncate'
          ),
      }),
    columnHelper.accessor('fecha_vencimiento', {
      header: t('CARTERA.FACTURAS.HEADERS.FECHA_VENCIMIENTO'),
      size: 130,
      cell: cellProps =>
        spanCell(
          formatearFecha(cellProps.getValue()),
          'text-body-main text-n-slate-11 whitespace-nowrap'
        ),
    }),
    columnHelper.accessor('dias_vencidos', {
      header: t('CARTERA.FACTURAS.HEADERS.DIAS_VENCIDOS'),
      size: 90,
      cell: cellProps =>
        spanCell(cellProps.getValue(), 'text-body-main text-n-slate-11'),
    }),
    columnHelper.accessor('valor_total', {
      header: t('CARTERA.FACTURAS.HEADERS.VALOR_TOTAL'),
      size: 140,
      cell: cellProps =>
        spanCell(
          formatearCop(cellProps.getValue()),
          'text-body-main text-n-slate-12 whitespace-nowrap tabular-nums'
        ),
    }),
    columnHelper.accessor('saldo_pendiente', {
      header: t('CARTERA.FACTURAS.HEADERS.SALDO_PENDIENTE'),
      size: 140,
      cell: cellProps =>
        spanCell(
          formatearCop(cellProps.getValue()),
          'text-body-main text-n-slate-12 whitespace-nowrap tabular-nums'
        ),
    }),
    columnHelper.accessor('tramo', {
      header: t('CARTERA.FACTURAS.HEADERS.TRAMO'),
      size: 120,
      cell: cellProps =>
        spanCell(
          t(`CARTERA.TRAMOS.${cellProps.getValue().toUpperCase()}`),
          'text-body-main text-n-slate-11 whitespace-nowrap capitalize'
        ),
    }),
    columnHelper.accessor('pagada', {
      header: t('CARTERA.FACTURAS.HEADERS.ESTADO'),
      size: 100,
      cell: cellProps =>
        h(
          'span',
          {
            class: [
              'rounded-full border px-2 py-0.5 text-[10px] whitespace-nowrap',
              cellProps.getValue()
                ? 'border-n-teal-6 bg-n-teal-3 text-n-teal-11'
                : 'border-n-amber-6 bg-n-amber-3 text-n-amber-11',
            ],
          },
          cellProps.getValue()
            ? t('CARTERA.FACTURAS.ESTADO_PAGADA')
            : t('CARTERA.FACTURAS.ESTADO_ABIERTA')
        ),
    }),
  ].filter(Boolean);
