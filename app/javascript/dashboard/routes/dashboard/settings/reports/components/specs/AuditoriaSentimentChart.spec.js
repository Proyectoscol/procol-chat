import { mount } from '@vue/test-utils';
import { fromUnixTime } from 'date-fns';
import { getUnixStartOfDay, getUnixEndOfDay } from 'helpers/DateHelper';
import AuditoriaSentimentChart from '../AuditoriaSentimentChart.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: key => key,
  }),
}));

// since/until son segundos UTC a proposito (Jan 10-12 2024, UTC medianoche a
// UTC 23:59:59) -- los tests de JS corren con TZ=UTC fijo (ver package.json),
// asi que fromUnixTime/startOfDay/endOfDay calzan 1:1 con Date.UTC sin
// depender de la zona horaria de quien ejecute el test.
const SINCE = Math.floor(Date.UTC(2024, 0, 10, 0, 0, 0) / 1000);
const UNTIL = Math.floor(Date.UTC(2024, 0, 12, 23, 59, 59) / 1000);

const SERIES = [
  { sentiment: 'positive', points: [{ date: '2024-01-11', count: 7 }] },
  { sentiment: 'neutral', points: [{ date: '2024-01-10', count: 2 }] },
  { sentiment: 'negative', points: [] },
];

describe('AuditoriaSentimentChart.vue', () => {
  const mountChart = (props = {}) =>
    mount(AuditoriaSentimentChart, {
      props: {
        series: SERIES,
        since: SINCE,
        until: UNTIL,
        bucket: 'day',
        ...props,
      },
    });

  it('shows the empty state when every series is all zeros', () => {
    const wrapper = mountChart({
      series: [
        { sentiment: 'positive', points: [] },
        { sentiment: 'neutral', points: [] },
        { sentiment: 'negative', points: [] },
      ],
    });

    expect(wrapper.text()).toContain('AUDITORIA_SENTIMENT_REPORTS.CHART.EMPTY');
    expect(wrapper.find('svg').exists()).toBe(false);
  });

  it('renders one point per day in the since/until range, 3 days here', () => {
    const wrapper = mountChart();

    // 3 lineas (una por sentiment), cada una con un path 'd' que tiene
    // exactamente 3 comandos (M + 2 L) -- uno por cada uno de los 3 dias
    // del rango.
    const paths = wrapper.findAll('path');
    expect(paths).toHaveLength(3);
    paths.forEach(path => {
      const commands = path.attributes('d').match(/[ML]/g);
      expect(commands).toHaveLength(3);
    });
  });

  // Regresion del bug ya corregido (commit 30abe4d1b) donde reparsear la
  // fecha de un bucket con `new Date(str)` la interpretaba como medianoche
  // UTC, corriendo la fecha emitida un dia hacia atras en timezones detras
  // de UTC. Si ese bug reapareciera, el `since`/`until` emitidos aqui
  // corresponderian al dia ANTERIOR al que realmente se clickeo.
  it('emits the exact calendar day clicked, with the breakdown by sentiment for that day', async () => {
    const wrapper = mountChart();
    const svg = wrapper.find('svg');

    // Stub de getBoundingClientRect: WIDTH interno del componente es 760,
    // asi que left:0/width:760 hace que clientX mapee 1:1 a coordenadas
    // internas del SVG sin tener que replicar su matematica de escalado.
    svg.element.getBoundingClientRect = () => ({ left: 0, width: 760 });

    // MARGIN.left=36, PLOT_WIDTH=708, 3 buckets (indices 0,1,2) -- x=390
    // cae exactamente en el indice 1 (2024-01-11, el del medio).
    await svg.trigger('click', { clientX: 390, clientY: 100 });

    expect(wrapper.emitted('selectBucket')).toHaveLength(1);
    const payload = wrapper.emitted('selectBucket')[0][0];

    const expectedDay = fromUnixTime(
      Math.floor(Date.UTC(2024, 0, 11, 0, 0, 0) / 1000)
    );
    expect(payload.since).toBe(getUnixStartOfDay(expectedDay));
    expect(payload.until).toBe(getUnixEndOfDay(expectedDay));
    expect(payload.counts).toEqual({ positive: 7, neutral: 0, negative: 0 });
  });
});
