#!/usr/bin/env python3
"""
Libreria compartida para parsear los archivos de agendas historicas del
batch 4 (urologia/ginecologia, Dr. Corrales y Dra. Cano) a una fila
normalizada por cita real.

Dos tipos de hoja, confirmados en ambos archivos:
  1. "Bloque por fecha": una fila de titulo con la fecha en texto libre,
     luego una fila de encabezados (variantes: TIPO DOC/DOC + NUMERO/NOMBRE/
     TELEFONO/ENTIDAD/PRODECIMIENTO/HORA), luego filas de datos hasta el
     siguiente bloque. Las columnas se ubican por NOMBRE de encabezado, no
     por posicion fija (el offset varia entre hojas).
  2. "Lista de espera": tabla limpia de una sola cabecera, con la primera
     columna = fecha real de solicitud (serial de Excel), DOCUMENTO/CC =
     cedula.

Cruce: para cada cita de un bloque, se busca en las hojas de lista de espera
la entrada con la MISMA cedula y la fecha de solicitud mas cercana (y previa
cuando es posible) a la fecha de la cita -- confirmado manualmente contra el
caso cedula 10125318 (AGENDAS DR CORRALES: cita 28-sep, solicitud real
21-sep, no la entrada del 9-jun que estaba mas lejos).

Estado por color de celda (pedido y confirmado por el usuario): blanco =
asistio, verde = no_show, cualquier otro color = 'revisar_color' (no se
adivina). Solo aplica a citas en el pasado; futuras quedan 'pendiente'.

Salida: un CSV con una fila por cita, listo para que un servicio de Rails la
use para corregir/crear Calendario::Appointment.
"""
import csv
import datetime
import re
import sys

import openpyxl

EXCEL_EPOCH = datetime.datetime(1899, 12, 30)

# 'DOC'/'TIPO DOC' -- Corrales usa 'TIPO DOC', Cano usa solo 'DOC '. Los
# bloques "PARTICULAR" (ej. "CONSULTA UROLOGIA...PARTICULAR" en AGENDAS DR
# CORRALES) usan un tercer dialecto sin columna de tipo de documento:
# CEDULA en vez de NUMERO, EPS en vez de ENTIDAD, y agregan VALOR (precio
# cobrado real).
HEADER_ALIASES = {
    'tipo_doc': ['TIPO DOC', 'DOC'],
    'numero': ['NUMERO', 'CEDULA'],
    'nombre': ['NOMBRE'],
    'telefono': ['TELEFONO'],
    'entidad': ['ENTIDAD', 'EPS'],
    'procedimiento': ['PRODECIMIENTO', 'PROCEDIMIENTO'],
    'hora': ['HORA'],
    'valor': ['VALOR'],
}

MESES = {
    'ENERO': 1, 'FEBRERO': 2, 'MARZO': 3, 'ABRIL': 4, 'MAYO': 5, 'JUNIO': 6,
    'JULIO': 7, 'AGOSTO': 8, 'SEPTIEMBRE': 9, 'OCTUBRE': 10, 'NOVIEMBRE': 11,
    'DICIEMBRE': 12,
}
# "28 DE SEPTIEMBRE", "02 DE ENERO DE 2026", "25 DE MAYO/26" (dia/mes abreviado)
DATE_RE = re.compile(
    r'(\d{1,2})\s+DE\s+(' + '|'.join(MESES) + r')(?:\s+DE\s+(\d{4}))?',
    re.IGNORECASE,
)
# Orden invertido: "JUNIO 24 DE 2026" (mes dia DE anio) -- confirmado real en
# DR VELEZ ("JUNIO 24 DE 2026 CISTOSCOPIAS").
DATE_RE_REVERSED = re.compile(
    r'(' + '|'.join(MESES) + r')\s+(\d{1,2})(?:\s+DE\s+(\d{4}))?',
    re.IGNORECASE,
)
NON_DATA_MARKERS = {'TARDE', 'MAÑANA', 'MANANA', 'TARDE ', 'MAÑANA ', 'PROCEDIMIENTO', 'PROCEDIMIENTOS'}
# "11.30", "7.00", "11:30" -- a veces la hora quedo como texto en vez de
# hora real de Excel (confirmado: DUVAN AUGUSTO ARIAS CARDONA, DR GAVIRIA).
TEXT_HORA_RE = re.compile(r'^(\d{1,2})[.:](\d{2})$')
GREEN_RGB = 'FF92D050'
DOC_TYPE_PREFIX_RE = re.compile(r'^(CC|CE|TI|PA|RC|PEP|PPT|PTP)[\s-]*', re.IGNORECASE)
DEFAULT_SLOT_MINUTES = 15


def classify_fill(cell):
    """Blanco/verde/otro -- confirmado con el usuario: blanco = asistio,
    verde = no_show. Cualquier otro color encontrado (amarillo, acento de
    tema) se marca 'otro' en vez de adivinar, porque el usuario no supo
    decirme que significan esos."""
    fill = cell.fill
    if not fill or not fill.fgColor:
        return 'blanco'
    fg = fill.fgColor
    if fg.type == 'theme' and fg.theme == 0:
        return 'blanco'
    if fg.type == 'rgb' and fg.rgb in (None, '00000000'):
        return 'blanco'
    if fg.type == 'rgb' and fg.rgb == GREEN_RGB:
        return 'verde'
    return 'otro'


def compute_estado(appt_datetime, color):
    if appt_datetime is None:
        return ''
    if appt_datetime > datetime.datetime.now():
        return 'pendiente'
    if color == 'blanco':
        return 'atendida'
    if color == 'verde':
        return 'no_show'
    return 'revisar_color'


def parse_text_hora(raw):
    """'11.30' -> time(11, 30). Misma convencion de hora que ya usan las
    celdas de hora REAL de Excel en este archivo (numero de hora tal cual,
    sin corregir AM/PM -- esa ambiguedad ya existe en todo el dataset, no es
    algo que este fallback deba resolver distinto al resto)."""
    if not isinstance(raw, str):
        return None
    match = TEXT_HORA_RE.match(raw.strip())
    if not match:
        return None
    hour, minute = int(match.group(1)), int(match.group(2))
    try:
        return datetime.time(hour, minute)
    except ValueError:
        return None


def split_doc_prefix(raw_numero):
    """'CE390604' -> ('390604', 'CE') -- el tipo de documento a veces queda
    pegado al numero por error de digitacion en la fuente. Devuelve
    (numero_limpio, prefijo_encontrado_o_None)."""
    text = str(raw_numero).strip()
    match = DOC_TYPE_PREFIX_RE.match(text)
    if match and len(text) > len(match.group(0)):
        return text[match.end():].strip(), match.group(1).upper()
    return text, None


def fill_missing_horas(entries):
    """entries: lista de dicts en orden de aparicion en el bloque, cada uno
    con 'hora' (datetime.time o None). Si falta, se interpola/extrapola
    contra los vecinos conocidos mas cercanos -- primero de la lista sin
    hora va antes del primero con hora, ultimo va despues del ultimo,
    intermedio se reparte proporcional entre los dos vecinos conocidos."""
    known_idx = [i for i, e in enumerate(entries) if e['hora'] is not None]
    if not known_idx:
        return  # ningun dato de referencia en todo el bloque -- no hay de donde interpolar

    # Moda, no promedio: un solo hueco real (ej. un paciente retirado de la
    # fuente sin correr la numeracion) puede inflar el promedio y producir
    # horas no redondas.
    intervals = []
    for a, b in zip(known_idx, known_idx[1:]):
        if b - a == 1:
            t1 = datetime.datetime.combine(datetime.date.today(), entries[a]['hora'])
            t2 = datetime.datetime.combine(datetime.date.today(), entries[b]['hora'])
            intervals.append(round((t2 - t1).total_seconds() / 60))
    if intervals:
        slot_minutes = max(set(intervals), key=lambda v: (intervals.count(v), -v))
    else:
        slot_minutes = DEFAULT_SLOT_MINUTES

    for i, entry in enumerate(entries):
        if entry['hora'] is not None:
            continue
        prev_idx = max((k for k in known_idx if k < i), default=None)
        next_idx = min((k for k in known_idx if k > i), default=None)
        candidates = []
        if prev_idx is not None:
            base = datetime.datetime.combine(datetime.date.today(), entries[prev_idx]['hora'])
            candidates.append(base + datetime.timedelta(minutes=slot_minutes * (i - prev_idx)))
        if next_idx is not None:
            base = datetime.datetime.combine(datetime.date.today(), entries[next_idx]['hora'])
            candidates.append(base - datetime.timedelta(minutes=slot_minutes * (next_idx - i)))
        if candidates:
            avg_seconds = sum(c.timestamp() for c in candidates) / len(candidates)
            entry['hora'] = datetime.datetime.fromtimestamp(avg_seconds).time()
            entry['hora_interpolada'] = True


def excel_serial_to_date(serial):
    if serial is None:
        return None
    if isinstance(serial, (datetime.datetime, datetime.date)):
        return serial
    try:
        return EXCEL_EPOCH + datetime.timedelta(days=float(serial))
    except (TypeError, ValueError):
        return None


def normalize_phone(raw):
    """Separa telefonos unidos por '-' y normaliza cada uno a +57XXXXXXXXXX
    para celulares colombianos (10 digitos, empieza por 3) -- mismo criterio
    que classifyContactQuery.js usado en el resto del proyecto este mes."""
    if raw is None:
        return []
    parts = re.split(r'[-/,]', str(raw))
    phones = []
    for part in parts:
        digits = re.sub(r'\D', '', part)
        if len(digits) == 10 and digits.startswith('3'):
            phones.append(f'+57{digits}')
        elif digits:
            phones.append(digits)
    return phones


def _row_has_header_markers(upper_cells):
    """('DOC'/'TIPO DOC' o 'CEDULA', el marcador de numero de documento en
    cualquiera de los 3 dialectos vistos) + 'NOMBRE' juntos en la misma fila
    -- suficiente para distinguir un encabezado real de una fila de datos."""
    has_doc_marker = any('DOC' in c or 'CEDULA' in c for c in upper_cells)
    return has_doc_marker and any('NOMBRE' in c for c in upper_cells)


def find_header_row(rows, start_idx):
    """Busca, a partir de start_idx, la fila que contiene marcadores de
    encabezado (ver _row_has_header_markers). Devuelve (idx, column_map) o
    (None, None) si no se encuentra en las siguientes 5 filas."""
    for idx in range(start_idx, min(start_idx + 5, len(rows))):
        row = rows[idx]
        upper_cells = {str(c).strip().upper() for c in row if c is not None}
        if _row_has_header_markers(upper_cells):
            column_map = {}
            for col_idx, cell in enumerate(row):
                if cell is None:
                    continue
                cell_upper = str(cell).strip().upper()
                for field, aliases in HEADER_ALIASES.items():
                    if any(alias in cell_upper for alias in aliases):
                        column_map[field] = col_idx
            return idx, column_map
    return None, None


def parse_block_date(text, default_year=2026):
    upper = text.upper()
    match = DATE_RE.search(upper)
    if match:
        day, month_name, year = match.groups()
    else:
        match = DATE_RE_REVERSED.search(upper)
        if not match:
            return None
        month_name, day, year = match.groups()
    month = MESES[month_name.upper()]
    year = int(year) if year else default_year
    try:
        return datetime.date(year, month, int(day))
    except ValueError:
        return None


def looks_like_header_row(row, column_map=None):
    upper_cells = {str(c).strip().upper() for c in row if c is not None}
    if _row_has_header_markers(upper_cells):
        return True
    # Encabezado repetido sin marcador DOC/CEDULA (esa columna vino vacia en
    # la repeticion) -- se detecta por la celda bajo 'nombre' siendo el
    # literal "NOMBRE", nunca un nombre real de paciente.
    if column_map and 'nombre' in column_map and column_map['nombre'] < len(row):
        nombre_cell = row[column_map['nombre']]
        if isinstance(nombre_cell, str) and nombre_cell.strip().upper() == 'NOMBRE':
            return True
    return False


def _flush_block(pending, appointments):
    """Interpola horas faltantes del bloque acumulado y las pasa, ya
    finalizadas (fecha+hora completa y estado por color), a la lista final."""
    if not pending:
        return
    fill_missing_horas(pending)
    for e in pending:
        appt_datetime = None
        if e['hora'] is not None:
            appt_datetime = datetime.datetime.combine(e['current_date'], e['hora'])
        e['cita_fecha_hora'] = appt_datetime.isoformat() if appt_datetime else ''
        e['hora_interpolada'] = e.get('hora_interpolada', False)
        e['estado'] = compute_estado(appt_datetime, e['color'])
        del e['hora'], e['current_date'], e['color']
        appointments.append(e)
    pending.clear()


def parse_block_sheet(ws, sheet_name, default_professional, source_file):
    rows = list(ws.iter_rows())
    all_values = [[c.value for c in r] for r in rows]
    appointments = []
    pending = []  # bloque en curso, se interpola/finaliza al cerrar
    current_date = None
    current_title = None
    # Mapa base: hojas como "PC MORCELACION" traen un encabezado una sola vez
    # al inicio (antes de cualquier titulo con fecha -- su titulo de hoja dice
    # "FECHA POR DEFINIR", sin fecha parseable) y luego varios sub-bloques de
    # fecha SIN encabezado propio despues. Sin este fallback, el primer
    # sub-bloque nunca encuentra columnas y toda la hoja parsea 0 citas.
    _, column_map = find_header_row(all_values, 0)
    idx = 0
    while idx < len(rows):
        row = rows[idx]
        values = [c.value for c in row]
        non_none = [v for v in values if v is not None]

        # Fila de titulo de bloque: exactamente 1-2 celdas de texto largo,
        # sin que sea un marcador TARDE/MAÑANA ni una fila de datos (que
        # siempre tiene un numero de cedula en alguna celda).
        if len(non_none) <= 3 and any(
            isinstance(v, str) and len(v.strip()) > 10
            and (DATE_RE.search(v.upper()) or DATE_RE_REVERSED.search(v.upper()))
            for v in non_none
        ):
            title_cell = next(
                v for v in non_none
                if isinstance(v, str) and (DATE_RE.search(v.upper()) or DATE_RE_REVERSED.search(v.upper()))
            )
            parsed = parse_block_date(title_cell)
            if parsed:
                _flush_block(pending, appointments)  # cierra el bloque anterior antes de abrir uno nuevo
                current_date = parsed
                current_title = title_cell.strip()
                # Siempre intenta refrescar -- distintos bloques pueden tener
                # distintos offsets de columna. Si NO aparece un encabezado
                # cerca (ej. "PC MORCELACION": un sub-bloque de fecha
                # incrustado sin encabezado propio despues), se conserva el
                # column_map ya establecido en vez de borrarlo.
                header_idx, found_map = find_header_row(all_values, idx + 1)
                if header_idx is not None:
                    column_map = found_map
                    idx = header_idx + 1
                    continue
            idx += 1
            continue

        if column_map is None or current_date is None:
            idx += 1
            continue

        # Encabezado repetido que no vino precedido de un titulo de bloque
        # reconocible (formato de fecha no contemplado) -- nunca es una fila
        # de datos, sin importar que el titulo haya fallado a parsear.
        if looks_like_header_row(values, column_map):
            idx += 1
            continue

        # Marcador TARDE/MAÑANA sin datos reales -- no es una fila de cita.
        if len(non_none) == 1 and isinstance(non_none[0], str) and non_none[0].strip().upper() in NON_DATA_MARKERS:
            idx += 1
            continue

        # ENTRADA:/SALIDA: -- registro de horario de entrada/salida de la
        # terapeuta (visto en FECHAS TERCARTERAPIA), no una cita de paciente.
        # Sin este filtro la hora quedaba leyendose como si fuera la cedula.
        if any(
            isinstance(v, str) and v.strip().upper().rstrip(': ') in ('ENTRADA', 'SALIDA')
            for v in non_none
        ):
            idx += 1
            continue

        numero = values[column_map['numero']] if 'numero' in column_map and column_map['numero'] < len(values) else None
        if numero is None or (isinstance(numero, str) and not numero.strip()):
            idx += 1
            continue

        cedula, doc_prefix_encontrado = split_doc_prefix(numero)
        hora = values[column_map['hora']] if 'hora' in column_map and column_map['hora'] < len(values) else None
        if not isinstance(hora, datetime.time):
            hora = parse_text_hora(hora)

        nombre = values[column_map['nombre']] if 'nombre' in column_map else None
        telefono_raw = values[column_map['telefono']] if 'telefono' in column_map else None
        entidad = values[column_map['entidad']] if 'entidad' in column_map else None
        procedimiento = values[column_map['procedimiento']] if 'procedimiento' in column_map else None
        valor = values[column_map['valor']] if 'valor' in column_map and column_map['valor'] < len(values) else None
        phones = normalize_phone(telefono_raw)
        color = classify_fill(row[column_map['numero']])

        pending.append({
            'cedula': cedula,
            'cedula_prefijo_tipo_doc_detectado': doc_prefix_encontrado or '',
            'nombre': str(nombre).strip() if nombre else '',
            'telefono_principal': phones[0] if phones else '',
            'telefono_secundario': phones[1] if len(phones) > 1 else '',
            'entidad': str(entidad).strip() if entidad else '',
            'procedimiento': str(procedimiento).strip() if procedimiento else '',
            'valor_cobrado': valor if isinstance(valor, (int, float)) else '',
            'profesional': default_professional or '',
            'fuente_hoja': sheet_name,
            'fuente_archivo': source_file,
            'fuente_bloque_titulo': current_title or '',
            'hora': hora,
            'current_date': current_date,
            'color': color,
        })
        idx += 1

    _flush_block(pending, appointments)  # cierra el ultimo bloque del archivo
    return appointments


def parse_waitlist_sheet(ws, sheet_name, source_file):
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        return []
    header = [str(c).strip().upper() if c is not None else '' for c in rows[0]]

    def col(*names):
        for i, h in enumerate(header):
            if any(n in h for n in names):
                return i
        return None

    col_fecha = 0  # primera columna siempre es la fecha de solicitud (serial), confirmado en todas las hojas
    col_doc = col('DOCUMENTO', 'CC')
    col_nombre = col('NOMBRE')
    col_fecha_prog = col('FECHA PROGRAMACION')
    col_obs = col('OBSERVACION')

    entries = []
    for row in rows[1:]:
        if col_doc is None or row[col_doc] is None:
            continue
        fecha = excel_serial_to_date(row[col_fecha])
        if fecha is None:
            continue
        entries.append({
            'cedula': str(row[col_doc]).strip(),
            'nombre': str(row[col_nombre]).strip() if col_nombre is not None and row[col_nombre] else '',
            'solicitud_fecha': fecha,
            'fecha_programacion_cruda': row[col_fecha_prog] if col_fecha_prog is not None else None,
            'observacion': str(row[col_obs]).strip() if col_obs is not None and row[col_obs] else '',
            'fuente_hoja': sheet_name,
            'fuente_archivo': source_file,
        })
    return entries


def closest_waitlist_entry(cedula, appt_date, waitlist_by_cedula):
    candidates = waitlist_by_cedula.get(cedula, [])
    if not candidates or appt_date is None:
        return None
    appt_date_only = appt_date.date() if isinstance(appt_date, datetime.datetime) else appt_date
    preceding = [c for c in candidates if c['solicitud_fecha'].date() <= appt_date_only]
    pool = preceding if preceding else candidates
    return min(pool, key=lambda c: abs((c['solicitud_fecha'].date() - appt_date_only).days))


FIELDNAMES = [
    'cedula', 'cedula_prefijo_tipo_doc_detectado', 'nombre', 'telefono_principal',
    'telefono_secundario', 'entidad', 'procedimiento', 'valor_cobrado', 'profesional', 'estado',
    'cita_fecha_hora', 'hora_interpolada', 'solicitud_fecha_real',
    'solicitud_fuente_hoja', 'fuente_hoja', 'fuente_archivo', 'fuente_bloque_titulo',
]


def run(source_path, out_path, block_sheets, waitlist_sheets):
    """block_sheets: dict {nombre_hoja: profesional_default_o_None}.
    waitlist_sheets: lista de nombres de hoja."""
    # read_only=False: necesario para leer el color de relleno de cada celda
    # (estado atendida/no_show se infiere del color, pedido explicito del usuario).
    wb = openpyxl.load_workbook(source_path, read_only=False, data_only=True)
    source_file = source_path.name

    all_appointments = []
    for sheet_name, default_professional in block_sheets.items():
        if sheet_name not in wb.sheetnames:
            print(f'AVISO: hoja "{sheet_name}" no encontrada, se omite', file=sys.stderr)
            continue
        ws = wb[sheet_name]
        appts = parse_block_sheet(ws, sheet_name, default_professional, source_file)
        print(f'{sheet_name}: {len(appts)} citas parseadas', file=sys.stderr)
        all_appointments.extend(appts)

    waitlist_entries = []
    for sheet_name in waitlist_sheets:
        if sheet_name not in wb.sheetnames:
            print(f'AVISO: hoja "{sheet_name}" no encontrada, se omite', file=sys.stderr)
            continue
        ws = wb[sheet_name]
        entries = parse_waitlist_sheet(ws, sheet_name, source_file)
        print(f'{sheet_name}: {len(entries)} entradas de lista de espera', file=sys.stderr)
        waitlist_entries.extend(entries)

    waitlist_by_cedula = {}
    for e in waitlist_entries:
        waitlist_by_cedula.setdefault(e['cedula'], []).append(e)

    matched = 0
    for appt in all_appointments:
        appt_date = datetime.datetime.fromisoformat(appt['cita_fecha_hora']) if appt['cita_fecha_hora'] else None
        match = closest_waitlist_entry(appt['cedula'], appt_date, waitlist_by_cedula)
        if match:
            appt['solicitud_fecha_real'] = match['solicitud_fecha'].date().isoformat()
            appt['solicitud_fuente_hoja'] = match['fuente_hoja']
            matched += 1
        else:
            appt['solicitud_fecha_real'] = ''
            appt['solicitud_fuente_hoja'] = ''

    print(f'Total citas: {len(all_appointments)}, con fecha de solicitud cruzada: {matched}', file=sys.stderr)

    with open(out_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES)
        writer.writeheader()
        for appt in all_appointments:
            writer.writerow(appt)

    print(f'Escrito: {out_path}', file=sys.stderr)
