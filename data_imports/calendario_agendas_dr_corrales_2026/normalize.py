#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Fase 2 de la normalizacion. Extiende lo construido en fase 1 (ver README.md,
"Hallazgos importantes" y CONTEXTO_NEGOCIO_FASE2.md para el porque de cada
regla nueva) con 3 fuentes adicionales confirmadas por el usuario:

  1. "AGENDAS DR CORRALES 2026 actualizado.xlsx" -- REEMPLAZA al archivo de
     fase 1 (mismas hojas + mas recientes + hoja nueva "CONS ROSALES",
     consultas de pacientes de Los Rosales del mismo Dr. Corrales que NO se
     tratan como agenda aparte). Las hojas "CLAVES" y "HORAS MEDICO APOYO"
     se leen (para el nombre de los profesionales de apoyo) pero nunca se
     parsean como citas -- CLAVES tiene credenciales reales, HORAS MEDICO
     APOYO es solo nota de quien cubrio un turno, no tiene pacientes.
  2. "URODINAMIAS 2026 (1).xlsx" -- SOLO 2 hojas: "LISTADO PC URODINAMIAS"
     (lista de espera, 654 filas, fechas 2025/2026 sanas) y "AGENDA
     URODINAMIAS " (agenda REAL de citas de María, 102 bloques, 06 de
     enero a 20 de noviembre 2026 -- corregido 2026-11-17: se habia
     descartado por error en la ronda anterior junto con las ~75 hojas de
     agenda diaria que SI tienen fechas de 2014 basura; esta hoja puntual
     es un bloque consolidado distinto, con fechas 2026 reales,
     confirmado por el usuario). El resto del archivo (las ~75 hojas de
     agenda diaria por fecha, "PREPARACION URODINAMIA", "PREPARACION BX")
     se descarta: fechas internas de 2014, basura de una plantilla vieja
     reciclada (confirmado por el usuario 2026-11-16) -- "AGENDAS DRA CANO
     2026.xlsx" es el mismo archivo, tampoco se lee.
  3. "PARTICULARES 2026.xlsx" -- SOLO "AGENDA DRA CANO" (ginecologia
     particular, Dra. Cano = "Lida") y "AGENDA  DR. CORRALES " (urologia
     particular). El resto del archivo (PENDIENTES, TERAPIAS, SEGIMIENTO
     TECART, MEDPLUS/SURA, RELACION CITOLOGIAS, TELEFONOS, Hoja1) queda
     fuera de esta ronda -- ver CONTEXTO_NEGOCIO_FASE2.md, son modulos
     nuevos (cartera de terapias de Mayra, conciliacion de facturacion,
     laboratorio) que no existen todavia en el sistema, no datos de
     agenda. "PARTICULARES 2026 (Autoguardado).xlsx" nunca se lee: es un
     autoguardado viejo sin ningun registro que no este ya en el
     principal (verificado documento por documento).

No es un parser generico de xlsx->DB: cada regla viene de inspeccionar a
mano el contenido real de estos archivos.

Uso: python3 normalize.py
Escribe: agendas_normalizadas.csv + revision_requerida.csv (en esta carpeta)
"""
import csv
import datetime
import re
import unicodedata
from pathlib import Path

import openpyxl

OUT_DIR = Path(__file__).resolve().parent
SOURCE_DIR = OUT_DIR / "source"
SOURCE_AGENDAS = SOURCE_DIR / "AGENDAS DR CORRALES 2026 actualizado.xlsx"
SOURCE_URODINAMIA_WAITLIST = SOURCE_DIR / "URODINAMIAS 2026 (1).xlsx"
SOURCE_PARTICULARES = SOURCE_DIR / "PARTICULARES 2026.xlsx"
DEFAULT_YEAR = 2026

MONTHS = {
    "ENERO": 1, "FEBRERO": 2, "FEBRRERO": 2, "MARZO": 3, "ABRIL": 4,
    "MAYO": 5, "JUNIO": 6, "JULIO": 7, "AGOSTO": 8, "SEPTIEMBRE": 9,
    "SEPTIEMRE": 9, "OCTUBRE": 10, "NOVIEMBRE": 11, "DICIEMBRE": 12,
}
MONTH_RE = "|".join(sorted(MONTHS.keys(), key=len, reverse=True))

# Doctoras/doctores que el titulo de bloque o una observacion puede mencionar
# -- "cruzar" el profesional real de la fila (ver README). El nombre del lado
# derecho es el que usa el sistema (coincide con Calendario::Professional#name
# sembrado en db/seeds.rb / creado por import_to_local.rb).
DOCTOR_ALIASES = [
    (re.compile(r"\bDRA?\.?\s*ESPA[NÑ]A\b", re.I), "Dra. España"),
    (re.compile(r"\bDR\.?\s*CORRALES\b", re.I), "Dr. Corrales"),
    (re.compile(r"\bDR\.?\s*DEVIA\b", re.I), "Dr. Devia"),
    (re.compile(r"\bDR\.?\s*VELEZ\b", re.I), "Dr. Velez"),
    (re.compile(r"\bDR\.?\s*GAVIRIA\b", re.I), "Dr. Gaviria"),
    (re.compile(r"\bDR\.?\s*HEREDIA\b", re.I), "Dr. Heredia"),
    (re.compile(r"\bDRA?\.?\s*CANO\b", re.I), "Dra. Cano"),
    # OJO: "DR ECHEVERRY", "DR PIEDRAHITA", "DR FEDERICO" y similares que
    # aparecen sueltos en OBSERVACION/notas o en HORAS MEDICO APOYO suelen
    # ser medicos de apoyo puntual o quien autorizo/refirio al paciente, NO
    # el profesional que atiende la cita -- a proposito NO estan en esta
    # lista (confirmado por el usuario 2026-11-16: no se les crea agenda
    # propia). Si aparecen sueltos, quedan intactos en notas para que el
    # humano decida, nunca reasignan el profesional de una fila.
]

# "Otro" (sin match) manda la fila entera a pendientes_sin_profesional.csv --
# NUNCA se importa como cita (ver prepare_import.py). Por eso cada typo real
# encontrado en revision_requerida.csv/pendientes que SI corresponde a un
# servicio real reconocible debe tener su propio patron aqui -- dejarlo sin
# mapear no es "neutral", es borrar una cita real que si paso (confirmado
# 2026-11-17 auditando 77 filas que habian caido en "Otro": varias eran
# citas reales -- ej. una Colposcopia atendida de Dra. Cano que nunca se
# cargo porque el servicio no existia en este mapa).
SERVICE_MAP = [
    # S* en ambas posiciones cubre CISTOSSCOPIA (doble S, typo real visto en
    # el Excel) ademas de CISTOSCOPIA/CISTOCOPIA/CITOSCOPIA.
    (re.compile(r"CI\.?S*TOS*COPIA", re.I), "Cistoscopia"),
    (re.compile(r"COLPOSCOPIA", re.I), "Colposcopia"),
    (re.compile(r"UROCULTIVO", re.I), "Urocultivo"),
    (re.compile(r"VASECTOMIA", re.I), "Vasectomia"),
    # UROFLUJO\w*METRIA tolera "UROFLUJOIMETRIA" (I de mas, typo real visto).
    (re.compile(r"UROFLUJO\w*METRIA", re.I), "Uroflujometria"),
    (re.compile(r"URODINAMIA", re.I), "Urodinamia"),
    (re.compile(r"BX\s*PROSTATA|BIOPSIA", re.I), "Biopsia de prostata"),
    (re.compile(r"LITOTRICIA", re.I), "Litotricia"),
    (re.compile(r"PESARIO", re.I), "Pesario"),
    (re.compile(r"SEXOLOGIA", re.I), "Sexologia"),
    (re.compile(r"CAUTERIZACION", re.I), "Cauterizacion"),
    (re.compile(r"CONIZACION", re.I), "Conizacion"),
    (re.compile(r"CONTROL", re.I), "Control"),
    (re.compile(r"POST\s*(QCO|QUIRURGIC|RTUP|LITOTRICIA|CATETER)", re.I), "Post quirurgico"),
    # RET(IR[O]?)? (no solo "RETIR\w*") cubre tambien el "RET CATETER" (sin
    # "IR"/"IRO", la variante MAS comun: 29 de las 34 filas con este
    # servicio real lo escriben asi). CAT[AE]T[EÉ]?R tolera "CATATER" (A en
    # vez de E) y "CATETR" (sin la ultima E).
    (re.compile(r"RET(IR[O]?)?\s*CAT[AE]T[EÉ]?R", re.I), "Retiro de cateter"),
    # CONSUL?+ / CONS+ cubre las variantes "CONS+CIT(OL)(+VPH)",
    # "CONSUL+CIT...", "VALORACION (CX)" -- todas son una consulta con un
    # examen adicional (citologia/VPH) o una valoracion, no un servicio
    # distinto; el detalle del examen queda en servicio_raw/notas, nunca se
    # modela como linea de facturacion aparte (ver CONTEXTO_NEGOCIO_FASE2.md).
    # CON?S+ULTA cubre "COSULTA" (sin la N) y "CONSSULTA" (S de mas) --
    # ambos typos reales vistos, ademas de "CONSULTA" normal.
    (re.compile(r"CON?S+ULTA|CONSU?L?\+|VALORACION", re.I), "Consulta"),
    (re.compile(r"CONSULTA", re.I), "Consulta"),
]

# Typos/variantes vistos en los archivos reales -- NO es una lista exhaustiva
# de EPS colombianas, es solo la limpieza de lo que efectivamente aparece.
EPS_FIXES = {
    "COLSSANITAS": "COLSANITAS",
    "MEDPPLUS": "MEDPLUS",
    "PIJAOS SALUD": "PIJAO SALUD",
    "PIJASO SALUD": "PIJAO SALUD",
    "PIJAO-SALUD": "PIJAO SALUD",
    "ROSALES": "LOS ROSALES",
    "LOR ROSALES": "LOS ROSALES",
    "SALUD PARA DOS": "SURA PARA DOS",
    "SURA SALUD PARA DOS": "SURA PARA DOS",
    "SURA  PARA DOS": "SURA PARA DOS",
    "FERROCARILES": "FERROCARRILES",
    "ALLINZ": "ALLIANZ",
    # Agregados en la auditoria de EPS 2026-11-17 (ver CONTEXTO_NEGOCIO_FASE2.md,
    # "Ronda 4") -- se habian creado ~30 Calendario::Payer duplicados por estos
    # typos antes de que existiera esta lista.
    "ASMED SALUD": "ASMET SALUD",
    "ASMET SALUDD": "ASMET SALUD",
    "PREVISEER": "PREVISER",
    "SOS BINESTAR": "SOS BIENESTAR",
    "SOS QUIMBAYAA": "SOS QUIMBAYA",
    "UNNISER": "UNISSER",
    "SEG BOLIVAR": "SEGUROS BOLIVAR",
    "SURA PLIZA": "SURA POLIZA",
    "REDVITAL": "RED VITAL",
    "SAALUD TOTAL": "SALUD TOTAL",
    "S.O.S": "SOS",
    "S.O.S.": "SOS",
    "SURA?": "SURA",
    "SENT HUMANO": "SENTIR HUMANO",
    "SENT. HUMAANO": "SENTIR HUMANO",
    "SENTIR": "SENTIR HUMANO",
    "SERVI HUMANO": "SERV HUMANO",
    "PARTICCULAR": "PARTICULAR",
    "PARTICU": "PARTICULAR",
    "PARTICULAAR": "PARTICULAR",
    "PARTICULARES": "PARTICULAR",
    "PARTICULRA": "PARTICULAR",
    "PARTICUKAR": "PARTICULAR",
    # Agregados al sumar la agenda real de Urodinamia (misma ronda,
    # "CASALUD" es una EPS real y comun ahi -- no es la misma lista que las
    # de arriba, solo trae sus propios typos nuevos).
    "CASASLUD": "CASALUD",
    "FERRCARRILES": "FERROCARRILES",
    "FUND LA LIGA": "FUNDACION LA LIGA",
    "FUND. LA LIGA": "FUNDACION LA LIGA",
    "SENTIR HUMENO": "SENTIR HUMANO",
    "SURA POLIOZA": "SURA POLIZA",
    "SURA?": "SURA",
    # Agregados al sumar PENDIENTES (ginecologia particular/EPS, misma ronda).
    "PARTICULAT": "PARTICULAR",
    "SEG. BOLIVAR": "SEGUROS BOLIVAR",
}


def clean_text(value):
    if value is None:
        return ""
    text = str(value)
    text = unicodedata.normalize("NFC", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def only_digits(value):
    return re.sub(r"\D", "", str(value or ""))


def split_phones(raw):
    """'3000000001-3000000002' -> ('3000000001', '3000000002').
    Numeros Colombia: 10 digitos (celular) o 7 (fijo Pereira/Armenia sin
    indicativo) -- cualquier otro largo se descarta (probablemente basura:
    cedula pegada, codigo de autorizacion, etc.) pero queda en `extra`."""
    if raw is None or raw == "":
        return "", "", ""
    text = str(raw)
    pieces = re.split(r"[-/,;]|\s{2,}", text)
    valid = []
    extra = []
    for piece in pieces:
        digits = only_digits(piece)
        if len(digits) in (7, 10):
            valid.append(digits)
        elif digits:
            extra.append(digits)
    phone1 = valid[0] if len(valid) > 0 else ""
    phone2 = valid[1] if len(valid) > 1 else ""
    extra_joined = "|".join(valid[2:] + extra)
    return phone1, phone2, extra_joined


def normalize_service(raw):
    text = clean_text(raw)
    for pattern, canonical in SERVICE_MAP:
        if pattern.search(text):
            return canonical, text
    return ("Otro" if text else ""), text


# "SOS" NO esta aqui a proposito: "SOS BIENESTAR", "SOS POS", "SOS SENIOR" y
# "SOS QUIMBAYA" parecen ser planes/marcas DISTINTAS de esa aseguradora, no
# una nota pegada -- tratarlos como prefijo colapsaria 4 entidades distintas
# en una sola "SOS" y perderia esa informacion real.
KNOWN_EPS_PREFIXES = [
    "LOS ROSALES", "PIJAO SALUD", "FOMAG", "SURA PARA DOS", "SURA POLIZA",
    "PARTICULAR", "COLSANITAS", "MEDPLUS", "COSMITET", "FERROCARRILES",
    "SANIDAD", "PREVISER", "ALLIANZ", "SAN JORGE",
]


def normalize_eps(raw):
    text = clean_text(raw).upper()
    text = re.sub(r"\s+", " ", text)
    text = EPS_FIXES.get(text, text)
    # "LOS ROSALES CONTROL CX 18" -> la entidad real es el prefijo; el resto
    # es una nota de seguimiento que se quedo pegada en esta columna por
    # error de digitacion en el Excel original.
    for prefix in KNOWN_EPS_PREFIXES:
        if text.startswith(prefix + " ") and text != prefix:
            return prefix
    return text


def find_doctor_mention(*texts):
    for text in texts:
        if not text:
            continue
        for pattern, name in DOCTOR_ALIASES:
            if pattern.search(text):
                return name
    return ""


def extract_date_from_text(text, default_year=DEFAULT_YEAR):
    """Encuentra una fecha en texto libre en cualquiera de los DOS ordenes
    que traen estos archivos: 'DIA DE MES[ DE AÑO]' (titulos de bloque de las
    hojas por-doctor/por-profesional, ej. "16 DE ENERO") o 'MES DIA' (columna
    FECHA PROGRAMACION de las hojas maestras, ej. "ABRIL 15", "ENERO 26 DRA
    ESPAÑA") -- se prueban ambos patrones, el que calce primero gana. Si no
    trae año explicito, asume default_year (titulo del archivo) -- ver
    README sobre por que el año de las celdas tipo datetime de FECHA
    PROGRAMACION NO es confiable y se descarta siempre."""
    if not text:
        return None, False
    upper = text.upper()
    day_first = re.search(
        rf"(\d{{1,2}})\s*(?:DE)?\s*({MONTH_RE})(?:\s*DE\s*(\d{{4}}))?", upper
    )
    month_first = re.search(rf"({MONTH_RE})\s+(\d{{1,2}})\b(?:\s*DE\s*(\d{{4}}))?", upper)

    candidates = []
    if day_first:
        candidates.append((int(day_first.group(1)), MONTHS[day_first.group(2)], day_first.group(3), day_first.start()))
    if month_first:
        candidates.append((int(month_first.group(2)), MONTHS[month_first.group(1)], month_first.group(3), month_first.start()))
    if not candidates:
        return None, False
    # El que aparece primero en el texto es el que se usa (el otro patron,
    # si tambien calzo, suele ser un falso positivo sobre el mismo texto).
    candidates.sort(key=lambda c: c[3])
    day, month, year_str, _ = candidates[0]
    year = int(year_str) if year_str else default_year
    explicit_year = bool(year_str)
    try:
        return datetime.date(year, month, day), explicit_year
    except ValueError:
        return None, False


def resolve_scheduled_date(value):
    """Para 'FECHA PROGRAMACION' de las hojas maestras: puede venir como
    datetime (con año-basura, ver README: 2005/2019/2002/1930... son
    artefactos de Excel auto-interpretando 'DD-MES' sin año, NO fechas
    reales) o como texto libre ('ENERO 26 DRA ESPAÑA'). Devuelve
    (fecha_iso_o_vacio, confianza, profesional_mencionado)."""
    if value in (None, ""):
        return "", "sin_fecha", ""
    if isinstance(value, (datetime.datetime, datetime.date)):
        month, day = value.month, value.day
        try:
            fecha = datetime.date(DEFAULT_YEAR, month, day)
        except ValueError:
            return "", "sin_fecha", ""
        return fecha.isoformat(), "estimada_sin_anio", ""
    text = clean_text(value)
    doctor = find_doctor_mention(text)
    fecha, explicit_year = extract_date_from_text(text)
    if fecha:
        return fecha.isoformat(), ("confirmada" if explicit_year else "estimada_sin_anio"), doctor
    return "", "sin_fecha", doctor


# --- Hojas "por profesional" (bloques con encabezado de fecha) -------------

BLOCK_RE = re.compile(
    rf"(\d{{1,2}})\s*(?:DE)?\s*({MONTH_RE})(?:\s*DE\s*(\d{{4}}))?", re.I
)
CONSULTORIO_RE = re.compile(r"CONSULTORIO\s*(\d+)", re.I)
SERVICE_HINT_RE = re.compile(
    r"PROCEDIMIENTOS?\s*MENORES|CISTOSCOPIAS?|POST\s*QUIRURGICOS?", re.I
)
BLOCK_TITLE_WORDS_RE = re.compile(r"CONSULTA|PROCEDIMIENTO|POST", re.I)


def parse_block_header(text, sheet_doctor, titulo_display=None):
    """'CONSULTAS LUNES 19 DE ENERO  CONSULTORIO 2' + que esa hoja ya trae
    'DR HEREDIA' en otra celda de la misma fila -> fecha + consultorio +
    pista de servicio. El profesional base es el de la hoja; se sobre-escribe
    si el titulo (o la celda vecina) menciona otro doctor -- eso es
    literalmente el caso de "servicio cruzado" que describio el usuario:
    la hoja se llama "DR CORRALES"/"AGENDAS" pero el Consultorio 2 de los
    lunes es en realidad agenda del Dr. Heredia."""
    match = BLOCK_RE.search(text.upper())
    fecha = None
    if match:
        day = int(match.group(1))
        month = MONTHS[match.group(2)]
        year = int(match.group(3)) if match.group(3) else DEFAULT_YEAR
        try:
            fecha = datetime.date(year, month, day)
        except ValueError:
            fecha = None
    consultorio = CONSULTORIO_RE.search(text.upper())
    service_hint = "Cistoscopia" if "CISTOSCOPIA" in text.upper() else (
        "Procedimiento menor" if SERVICE_HINT_RE.search(text) else ""
    )
    doctor = find_doctor_mention(text) or sheet_doctor
    return {
        "fecha": fecha,
        "consultorio": consultorio.group(1) if consultorio else "",
        "service_hint": service_hint,
        "profesional": doctor,
        "titulo_raw": clean_text(titulo_display if titulo_display is not None else text),
    }


def resolve_time(raw_time):
    """Hora de Excel sin AM/PM explicito. Verificado contra los bloques que
    SI traen sub-encabezado explicito 'MAÑANA'/'TARDE' en las hojas por-
    profesional: bajo 'MAÑANA' SOLO aparecen horas 7-11 (0 casos de 1-6),
    bajo 'TARDE' SOLO aparecen horas 1-5 (0 casos de 7-11) -- es decir, este
    consultorio nunca atiende antes de las 7am ni despues de las 6pm, asi
    que la ambiguedad del reloj de 12h se resuelve con una regla fija, sin
    necesidad de rastrear secuencias ni sub-encabezados:
      hora 1-6   -> siempre TARDE (+12)
      hora 7-11  -> siempre MAÑANA (sin cambio)
      hora 12    -> mediodia (sin cambio)
    Casi siempre raw_time es datetime.time; una celda aislada vino como
    texto "11.30" (punto en vez de dos puntos) -- se tolera ese formato en
    vez de descartar la hora."""
    if raw_time is None:
        return None
    if isinstance(raw_time, str):
        match = re.match(r"^(\d{1,2})[.:,](\d{2})$", raw_time.strip())
        if not match:
            return None
        h, m = int(match.group(1)), int(match.group(2))
    else:
        h, m = raw_time.hour, raw_time.minute
    if 1 <= h <= 6:
        h += 12
    return datetime.time(h, m)


# "Hoy" para efectos de que fecha es pasado/futuro -- fijo (no datetime.date.today())
# porque el reloj real de la maquina puede no coincidir con la fecha de
# referencia del negocio (ver CONTEXTO_NEGOCIO_FASE2.md); confirmar antes de
# reusar este script mucho mas adelante en el tiempo.
TODAY = datetime.date(2026, 11, 16)

# Confirmado por el usuario 2026-11-16, fila por fila contra el Excel real:
# en las hojas de agenda (por profesional Y particulares), una fila de
# fecha PASADA sin relleno (blanco/sin color) significa que el paciente
# ASISTIO; una fila en VERDE (#92D050, el mismo verde que en otras hojas
# del archivo significa otra cosa -- cada hoja tiene su propia convencion
# de color, no se reusa este mapa en otra hoja) significa que NO ASISTIO.
# Una fecha futura nunca se marca (no hay desenlace todavia). Cualquier
# otro color no se adivina -- se manda a revision humana.
NO_SHOW_RGB = "FF92D050"
ATTENDED_FILL_RGB = {"FFFFFFFF", "FFF6F8F9", "00000000"}


def attendance_from_fill(cell, fecha):
    try:
        fg = cell.fill.fgColor
        rgb = fg.rgb if isinstance(fg.rgb, str) else None
    except Exception:
        rgb = None
    is_plain = rgb in ATTENDED_FILL_RGB or rgb is None
    # Fecha futura (o sin fecha): todavia no hay desenlace -- NUNCA se marca,
    # ni "asistio" ni "no_show", incluso si la celda ya trae un color (bug
    # real encontrado 2026-11-17: el chequeo de fecha pasada solo protegia
    # el caso "asistio", una fila verde en fecha futura se marcaba no_show
    # igual). Se manda a revisar en vez de adivinar un desenlace que no paso.
    if not fecha or fecha >= TODAY:
        return "" if is_plain else "revisar_color"
    if rgb == NO_SHOW_RGB:
        return "no_show"
    return "attended" if is_plain else "revisar_color"


DOCTOR_SHEETS = {
    "AGENDAS ": "Dr. Corrales",
    "DR DEVIA ": "Dr. Devia",
    "DR VELEZ": "Dr. Velez",
    "DR GAVIRIA": "Dr. Gaviria",
    "DRA ESPAÑA ": "Dra. España",
    # Consultas de pacientes de Los Rosales del mismo Dr. Corrales -- NO es
    # una agenda aparte, es un recorte/reporte por entidad (confirmado por
    # el usuario 2026-11-16: "siguen siendo pacientes del mismo doctor").
    "CONS ROSALES": "Dr. Corrales",
}


def process_doctor_sheet(wb, sheet_name, sheet_doctor, rows_out, review_out):
    ws = wb[sheet_name]
    current_block = None

    for row_idx, row in enumerate(
        ws.iter_rows(min_row=1, max_row=ws.max_row, values_only=True), start=1
    ):
        non_none = [c for c in row if c is not None]
        texts = [clean_text(c) for c in row if isinstance(c, str) and clean_text(c)]

        # Sub-encabezado "MAÑANA"/"TARDE" dentro de un bloque: es solo
        # decorativo para quien lee el Excel (resolve_time ya no lo
        # necesita, ver su docstring), pero igual no es una fila de datos.
        if len(non_none) == 1 and texts and texts[0].upper().rstrip(".") in ("MAÑANA", "TARDE"):
            continue

        # Encabezado de bloque: una sola celda larga con fecha en texto, o
        # la fila clasica "CONSULTAS ... DE ... CONSULTORIO N ... DR X". El
        # nombre del doctor real a veces NO esta en esa misma celda sino en
        # otra columna de la MISMA fila (ej. "CONSULTORIO 2" en una celda y
        # 'DR HEREDIA' en otra celda de esa fila) -- por eso se pasa toda la
        # fila, no solo texts[0], al buscar el profesional mencionado.
        if texts and any(BLOCK_RE.search(t.upper()) for t in texts) and BLOCK_TITLE_WORDS_RE.search(texts[0]):
            current_block = parse_block_header(" ".join(texts), sheet_doctor, titulo_display=texts[0])
            continue

        # Fila de sub-encabezado de columnas ("TIPO DOC", "NUMERO", ...): sin dato real.
        if "TIPO DOC" in [str(c).strip().upper() if c else "" for c in row]:
            continue

        # Fila de datos: busca la celda con TIPO DOC valido (CC/TI/CE/RC/...)
        tipo_doc_idx = None
        for i, v in enumerate(row):
            if isinstance(v, str) and v.strip().upper() in (
                "CC", "TI", "CE", "RC", "PEP", "PPT", "NIT"
            ):
                tipo_doc_idx = i
                break
        if tipo_doc_idx is None or current_block is None:
            continue

        tipo_doc = row[tipo_doc_idx].strip().upper()
        numero = row[tipo_doc_idx + 1] if tipo_doc_idx + 1 < len(row) else None
        nombre = row[tipo_doc_idx + 2] if tipo_doc_idx + 2 < len(row) else None
        telefono_raw = row[tipo_doc_idx + 3] if tipo_doc_idx + 3 < len(row) else None
        entidad = row[tipo_doc_idx + 4] if tipo_doc_idx + 4 < len(row) else None
        procedimiento = row[tipo_doc_idx + 5] if tipo_doc_idx + 5 < len(row) else None
        hora_raw = row[tipo_doc_idx + 6] if tipo_doc_idx + 6 < len(row) else None
        notas = [
            clean_text(c) for c in row[tipo_doc_idx + 7:] if isinstance(c, str) and clean_text(c)
        ]

        if not clean_text(nombre):
            continue  # fila vacia dentro del bloque (separador visual)

        # PROCEDIMIENTO a veces trae el nombre del doctor real pegado (el
        # "servicio cruzado" que menciono el usuario) -- ej. "POST QCO JUNIO
        # 12 DRA ESPAÑA" dentro de la hoja AGENDAS. Esa SI es una
        # reasignacion real y gana sobre el profesional del bloque/hoja.
        # Una mencion de doctor en NOTAS en cambio suele ser quien
        # autorizo/remitio al paciente (ej. "DR ECHEVERRY-AUT DRA CANO"),
        # no quien lo atiende -- esa solo se deja marcada para revision,
        # nunca reasigna el profesional.
        procedimiento_text = clean_text(procedimiento)
        doctor_en_procedimiento = find_doctor_mention(procedimiento_text)
        doctor_en_notas = find_doctor_mention(" ".join(notas))
        profesional_final = doctor_en_procedimiento or current_block["profesional"]

        servicio_normalizado, servicio_raw = normalize_service(procedimiento_text)
        if not servicio_normalizado and current_block["service_hint"]:
            servicio_normalizado = current_block["service_hint"]

        hora_resuelta = resolve_time(hora_raw)

        telefono1, telefono2, telefono_extra = split_phones(telefono_raw)
        numero_doc = only_digits(numero)

        asistencia = attendance_from_fill(
            ws.cell(row=row_idx, column=tipo_doc_idx + 3), current_block["fecha"]
        )

        out = {
            "fuente_hoja": sheet_name.strip(),
            "fuente_fila": row_idx,
            "tipo_registro": "agenda_profesional",
            "tipo_documento": tipo_doc,
            "numero_documento": numero_doc,
            "nombre": clean_text(nombre),
            "telefono_1": telefono1,
            "telefono_2": telefono2,
            "telefono_extra": telefono_extra,
            "entidad_eps": normalize_eps(entidad),
            "especialidad": "Urologia",
            "profesional": profesional_final,
            "servicio_normalizado": servicio_normalizado,
            "servicio_raw": servicio_raw,
            "fecha_programada": current_block["fecha"].isoformat() if current_block["fecha"] else "",
            "fecha_confianza": "confirmada" if current_block["fecha"] else "sin_fecha",
            "hora_programada": hora_resuelta.strftime("%H:%M") if hora_resuelta else "",
            "estado": "programada" if current_block["fecha"] else "lista_espera",
            "asistencia": asistencia,
            "consultorio": current_block["consultorio"],
            "observacion": "",
            "notas_adicionales": " | ".join(notas),
            "bloque_titulo_raw": current_block["titulo_raw"],
        }
        rows_out.append(out)

        if asistencia == "revisar_color":
            review_out.append({**out, "motivo_revision": "color de fila no reconocido (ni blanco ni verde) para una fecha pasada -- revisar a mano"})

        if not numero_doc or not telefono1 or not out["fecha_programada"]:
            review_out.append({**out, "motivo_revision": "dato_clave_faltante (documento/telefono/fecha)"})
        if doctor_en_procedimiento and doctor_en_procedimiento != current_block["profesional"]:
            review_out.append({
                **out,
                "motivo_revision": (
                    f"profesional cruzado: hoja/bloque indica "
                    f"'{current_block['profesional']}' pero el procedimiento menciona "
                    f"'{doctor_en_procedimiento}'"
                ),
            })
        elif doctor_en_notas and doctor_en_notas != profesional_final:
            review_out.append({
                **out,
                "motivo_revision": (
                    f"las notas mencionan a '{doctor_en_notas}' (posible autorizo/remitio, "
                    f"NO se reasigno el profesional) -- confirmar si aplica"
                ),
            })
        elif current_block["profesional"] != sheet_doctor:
            review_out.append({
                **out,
                "motivo_revision": (
                    f"profesional cruzado: la hoja es '{sheet_doctor}' pero este bloque/"
                    f"consultorio es de '{current_block['profesional']}'"
                ),
            })


# --- Hojas "maestras" (CONSULTAS / PROCEDIMIENTOS UROLOGIA) ---------------

def parse_registration_date(raw):
    """Columna 'FECHA' de las hojas maestras (y columna 1 de LISTADO PC
    URODINAMIAS) -- confirmado por el usuario 2026-11-17: NO es la fecha de
    la cita, es la fecha en que el paciente se registro pidiendo cupo. Sirve
    para la estadistica real de "dias esperando" y para que el orden "mas
    antiguas primero" de la lista de espera tenga sentido -- antes se
    perdia del todo (nunca se leia esta columna) o quedaba solo como nota de
    texto, nunca como el created_at real de la entrada."""
    if isinstance(raw, (datetime.datetime, datetime.date)):
        d = raw.date() if isinstance(raw, datetime.datetime) else raw
        return d.isoformat()
    if isinstance(raw, str):
        fecha, _ = extract_date_from_text(raw)
        if fecha:
            return fecha.isoformat()
    return ""


def process_master_sheet(
    wb, sheet_name, tipo_registro, rows_out, review_out,
    column_aliases=None, default_especialidad="Urologia", default_profesional="",
    default_servicio="",
):
    """column_aliases: {nombre_esperado: nombre_real_en_esta_hoja} -- para
    hojas con el mismo tipo de caos (bloque "FECHA" sin fecha confiable,
    profesional mencionado dentro de esa misma columna) pero encabezados
    distintos (ej. PENDIENTES de PARTICULARES.xlsx usa "CONTACTO"/"ENTIDAD"
    en vez de "TELEFONOS"/"EPS"). default_profesional: si la hoja no trae
    ninguna mencion de doctor, a quien asignarle la fila (PENDIENTES es
    casi siempre de Dra. Cano, a diferencia de CONSULTAS UROLOGIA que se
    deja vacio y va a pendientes_sin_profesional si nadie lo menciona).
    default_servicio: si la hoja no tiene columna PROCEDIMIENTO confiable,
    que servicio asumir en vez de dejarlo vacio (-> "Otro" -> se descarta)."""
    ws = wb[sheet_name]
    header_row = next(ws.iter_rows(min_row=1, max_row=1, values_only=True))
    header = [clean_text(c).upper() if c else "" for c in header_row]
    idx = {}
    for i, h in enumerate(header):
        if h and h not in idx:  # primera ocurrencia (hay 'CIUDAD' repetida)
            idx[h] = i
    for expected, real in (column_aliases or {}).items():
        if expected not in idx and real in idx:
            idx[expected] = idx[real]
    doc_col = idx.get("DOCUMENTO", idx.get("CC"))

    for row_idx, row in enumerate(
        ws.iter_rows(min_row=2, max_row=ws.max_row, values_only=True), start=2
    ):
        documento = row[doc_col] if doc_col is not None else None
        nombre = row[idx["NOMBRE"]] if "NOMBRE" in idx else None
        if documento is None and not clean_text(nombre):
            continue

        observacion = clean_text(row[idx["OBSERVACION"]]) if "OBSERVACION" in idx else ""
        fecha_prog_raw = row[idx["FECHA PROGRAMACION"]] if "FECHA PROGRAMACION" in idx else None
        fecha_iso, fecha_confianza, doctor_en_fecha = resolve_scheduled_date(fecha_prog_raw)
        telefono_raw = row[idx["TELEFONOS"]] if "TELEFONOS" in idx else None
        telefono1, telefono2, telefono_extra = split_phones(telefono_raw)
        if "PROCEDIMIENTO" in idx:
            procedimiento_text = clean_text(row[idx["PROCEDIMIENTO"]])
            servicio_normalizado, servicio_raw = normalize_service(procedimiento_text)
        else:
            # Sin columna de procedimiento confiable -- se asume el default
            # de la hoja (ej. "Consulta" para PENDIENTES de ginecologia) en
            # vez de dejarlo vacio, que normalize_service("") NO convierte
            # en "Otro" (queda "" sin marca) pero prepare_import.py igual lo
            # trata como "sin servicio" y la fila nunca se importa.
            servicio_normalizado, servicio_raw = default_servicio, ""
        entidad = row[idx["EPS"]] if "EPS" in idx else None
        doctor_en_obs = find_doctor_mention(observacion)
        profesional_final = doctor_en_fecha or doctor_en_obs or default_profesional
        # Columna 1 (A) SIEMPRE es la fecha de solicitud, pase lo que pase en
        # su encabezado -- en "CONSULTAS UROLOGIA" ese encabezado es
        # literalmente el numero "22" (basura real del Excel, no texto
        # "FECHA"), asi que buscar por nombre de columna (idx["FECHA"])
        # nunca la encontraba. En "PROCEDIMIENTOS UROLOGIA" si dice "FECHA"
        # pero es la MISMA columna 1 -- usar la posicion fija es consistente
        # en ambas hojas.
        fecha_solicitud = parse_registration_date(row[0])

        out = {
            "fuente_hoja": sheet_name.strip(),
            "fuente_fila": row_idx,
            "tipo_registro": tipo_registro,
            "tipo_documento": "CC",
            "numero_documento": only_digits(documento),
            "nombre": clean_text(nombre),
            "telefono_1": telefono1,
            "telefono_2": telefono2,
            "telefono_extra": telefono_extra,
            "entidad_eps": normalize_eps(entidad),
            "especialidad": clean_text(row[idx["ESPECIALIDAD"]]) if "ESPECIALIDAD" in idx else default_especialidad,
            "profesional": profesional_final,
            "servicio_normalizado": servicio_normalizado,
            "servicio_raw": servicio_raw,
            "fecha_programada": fecha_iso,
            "fecha_confianza": fecha_confianza,
            "hora_programada": "",
            "estado": "programada" if fecha_iso else "lista_espera",
            "asistencia": "",
            "fecha_solicitud": fecha_solicitud,
            "consultorio": "",
            "observacion": observacion,
            "notas_adicionales": "",
            "bloque_titulo_raw": clean_text(fecha_prog_raw) if isinstance(fecha_prog_raw, str) else "",
        }
        rows_out.append(out)

        if not out["numero_documento"] or not telefono1:
            review_out.append({**out, "motivo_revision": "dato_clave_faltante (documento/telefono)"})
        if fecha_confianza == "estimada_sin_anio":
            review_out.append({
                **out,
                "motivo_revision": "fecha sin año explicito en el Excel -- se asumio 2026, confirmar",
            })
        if out["estado"] == "lista_espera" and not profesional_final:
            review_out.append({
                **out,
                "motivo_revision": "sin fecha y sin profesional mencionado -- revisar a mano para lista de espera",
            })


# --- Hojas "particulares" (PARTICULARES 2026.xlsx) ------------------------
# Mismo concepto de bloque con fecha en el titulo, pero SIN fila "TIPO DOC":
# el encabezado de columnas es HORA/CEDULA/NOMBRE/TELEFONO/EPS/PROCEDIMIENTO
# /VALOR (precio cobrado real, ver CONTEXTO_NEGOCIO_FASE2.md). No se modela
# el VALOR como campo de citas todavia -- se preserva como nota de texto.

PARTICULAR_SHEETS = {
    "AGENDA DRA CANO": "Dra. Cano",
    "AGENDA  DR. CORRALES ": "Dr. Corrales",
}


def process_particular_sheet(wb, sheet_name, sheet_doctor, rows_out, review_out):
    ws = wb[sheet_name]
    current_block = None
    hora_col = None  # indice (0-based) de la columna HORA del bloque de datos actual

    for row_idx, row in enumerate(
        ws.iter_rows(min_row=1, max_row=ws.max_row, values_only=True), start=1
    ):
        texts = [clean_text(c) for c in row if isinstance(c, str) and clean_text(c)]

        if texts and any(BLOCK_RE.search(t.upper()) for t in texts) and BLOCK_TITLE_WORDS_RE.search(texts[0]):
            current_block = parse_block_header(" ".join(texts), sheet_doctor, titulo_display=texts[0])
            hora_col = None
            continue

        # Fila de encabezado de columnas: ubica HORA (exacta, no substring,
        # para no confundir con "AHORA" o similar).
        header_match = next(
            (i for i, v in enumerate(row) if isinstance(v, str) and v.strip().upper() == "HORA"), None
        )
        if header_match is not None:
            hora_col = header_match
            continue

        if current_block is None or hora_col is None:
            continue

        cedula_idx, nombre_idx, telefono_idx = hora_col + 1, hora_col + 2, hora_col + 3
        eps_idx, procedimiento_idx, valor_idx = hora_col + 4, hora_col + 5, hora_col + 6
        if nombre_idx >= len(row):
            continue
        nombre = row[nombre_idx]
        if not clean_text(nombre) or clean_text(nombre).upper() == "NOMBRE":
            continue  # fila vacia o encabezado repetido dentro del bloque

        hora_raw = row[hora_col] if hora_col < len(row) else None
        numero = row[cedula_idx] if cedula_idx < len(row) else None
        telefono_raw = row[telefono_idx] if telefono_idx < len(row) else None
        entidad = row[eps_idx] if eps_idx < len(row) else None
        procedimiento = row[procedimiento_idx] if procedimiento_idx < len(row) else None
        valor = row[valor_idx] if valor_idx < len(row) else None
        notas = [
            clean_text(c) for c in row[valor_idx + 1:] if isinstance(c, str) and clean_text(c)
        ]
        if valor not in (None, ""):
            notas.append(f"[VALOR COBRADO: {valor}]")

        hora_resuelta = resolve_time(hora_raw)
        telefono1, telefono2, telefono_extra = split_phones(telefono_raw)
        numero_doc = only_digits(numero)
        procedimiento_text = clean_text(procedimiento)
        servicio_normalizado, servicio_raw = normalize_service(procedimiento_text)
        doctor_en_procedimiento = find_doctor_mention(procedimiento_text)
        profesional_final = doctor_en_procedimiento or current_block["profesional"]

        asistencia = attendance_from_fill(
            ws.cell(row=row_idx, column=nombre_idx + 1), current_block["fecha"]
        )

        out = {
            "fuente_hoja": sheet_name.strip(),
            "fuente_fila": row_idx,
            "tipo_registro": "agenda_particular",
            "tipo_documento": "CC",
            "numero_documento": numero_doc,
            "nombre": clean_text(nombre),
            "telefono_1": telefono1,
            "telefono_2": telefono2,
            "telefono_extra": telefono_extra,
            "entidad_eps": normalize_eps(entidad) or "PARTICULAR",
            "especialidad": "Urologia" if sheet_doctor == "Dr. Corrales" else "Ginecologia",
            "profesional": profesional_final,
            "servicio_normalizado": servicio_normalizado,
            "servicio_raw": servicio_raw,
            "fecha_programada": current_block["fecha"].isoformat() if current_block["fecha"] else "",
            "fecha_confianza": "confirmada" if current_block["fecha"] else "sin_fecha",
            "hora_programada": hora_resuelta.strftime("%H:%M") if hora_resuelta else "",
            "estado": "programada" if current_block["fecha"] else "lista_espera",
            "asistencia": asistencia,
            "consultorio": "",
            "observacion": "",
            "notas_adicionales": " | ".join(notas),
            "bloque_titulo_raw": current_block["titulo_raw"],
        }
        rows_out.append(out)

        if not numero_doc or not telefono1 or not out["fecha_programada"]:
            review_out.append({**out, "motivo_revision": "dato_clave_faltante (documento/telefono/fecha)"})
        if asistencia == "revisar_color":
            review_out.append({**out, "motivo_revision": "color de fila no reconocido (ni blanco ni verde) para una fecha pasada -- revisar a mano"})


# --- Lista de espera de Urodinamia (LISTADO PC URODINAMIAS) ---------------
# Regla de color confirmada fila por fila contra las 654 filas reales (ver
# CONTEXTO_NEGOCIO_FASE2.md): morado (tema Accent4, #8064A2) = ya paso a la
# tabla de agendas, NO sigue en lista de espera; azul claro (#00B0F0) = grupo
# FOMAG/neurologia con convenio terminado, tampoco se agenda; blanco/sin
# relleno = sigue pendiente, SI se importa a la lista de espera real.
AGENDADO_THEME_INDEX = 7  # Accent4 del tema de Office (#8064A2) -- ver inventario
CONVENIO_TERMINADO_RGB = "FF00B0F0"
WHITE_RGB = {"FFFFFFFF", "FFF6F8F9", "00000000"}


def fill_classification(cell):
    try:
        fg = cell.fill.fgColor
        if isinstance(fg.rgb, str) and fg.rgb in WHITE_RGB:
            return "blanco"
        if isinstance(fg.rgb, str) and fg.rgb == CONVENIO_TERMINADO_RGB:
            return "convenio_terminado"
        if fg.theme == AGENDADO_THEME_INDEX:
            return "ya_agendado"
        if isinstance(fg.rgb, str) and fg.rgb.startswith("FF"):
            return "otro_color"
    except Exception:
        pass
    return "blanco"  # sin relleno explicito -> se trata como blanco (pendiente)


# Agenda REAL de Urodinamia/Uroflujometria -- corregido 2026-11-17: al
# descartar "URODINAMIAS 2026 (1).xlsx" por las ~75 hojas de agenda diaria
# con fechas de 2014 (ver Ronda 2), se descarto de mas: ESTA hoja puntual
# ("AGENDA URODINAMIAS ") es un bloque UNICO consolidado (no un sheet por
# dia como las otras) con 102 bloques de fecha, TODOS en 2026 (06 de enero
# a 20 de noviembre), mismo layout de "titulo + encabezado + filas" que las
# demas agendas por-profesional. El usuario confirmo que es real. Columnas
# fijas (no hay fila "TIPO DOC" para buscar dinamicamente como en
# process_doctor_sheet): TIPO DOCUMENTO/DOCUMENTO/NOMBRES/TELEFONOS/EPS/
# EDAD/ESPECIALIDAD/PROCEDIMIENTO/HORA. La columna 1 (antes de TIPO
# DOCUMENTO) trae fechas-basura (2022, 2002, 2029...) igual que las hojas
# maestras de fase 1 -- se ignora, la fecha real es la del titulo del
# bloque. Misma regla de color que las demas agendas (blanco=asistio,
# verde=no asistio, ver attendance_from_fill).
URODINAMIA_BLOCK_RE = re.compile(r"URODINAMIA", re.I)


def process_urodinamia_agenda(wb, rows_out, review_out):
    ws = wb["AGENDA URODINAMIAS "]
    current_block = None

    for row_idx in range(1, ws.max_row + 1):
        titulo = ws.cell(row=row_idx, column=2).value
        if isinstance(titulo, str) and URODINAMIA_BLOCK_RE.search(titulo) and BLOCK_RE.search(titulo.upper()):
            current_block = parse_block_header(titulo, "María", titulo_display=titulo)
            continue

        tipo_doc = ws.cell(row=row_idx, column=2).value
        if isinstance(tipo_doc, str) and tipo_doc.strip().upper() == "TIPO DOCUMENTO":
            continue  # fila de encabezado de columnas

        nombre = ws.cell(row=row_idx, column=4).value
        if current_block is None or not clean_text(nombre):
            continue

        numero = ws.cell(row=row_idx, column=3).value
        telefono_raw = ws.cell(row=row_idx, column=5).value
        entidad = ws.cell(row=row_idx, column=6).value
        procedimiento = ws.cell(row=row_idx, column=9).value
        hora_raw = ws.cell(row=row_idx, column=10).value
        nota = clean_text(ws.cell(row=row_idx, column=11).value)

        hora_resuelta = resolve_time(hora_raw)
        telefono1, telefono2, telefono_extra = split_phones(telefono_raw)
        numero_doc = only_digits(numero)
        servicio_normalizado, servicio_raw = normalize_service(procedimiento)
        asistencia = attendance_from_fill(ws.cell(row=row_idx, column=4), current_block["fecha"])

        out = {
            "fuente_hoja": "AGENDA URODINAMIAS",
            "fuente_fila": row_idx,
            "tipo_registro": "agenda_profesional",
            "tipo_documento": "CC",
            "numero_documento": numero_doc,
            "nombre": clean_text(nombre),
            "telefono_1": telefono1,
            "telefono_2": telefono2,
            "telefono_extra": telefono_extra,
            "entidad_eps": normalize_eps(entidad),
            "especialidad": "Urologia",
            "profesional": "María",
            "servicio_normalizado": servicio_normalizado,
            "servicio_raw": servicio_raw,
            "fecha_programada": current_block["fecha"].isoformat() if current_block["fecha"] else "",
            "fecha_confianza": "confirmada" if current_block["fecha"] else "sin_fecha",
            "hora_programada": hora_resuelta.strftime("%H:%M") if hora_resuelta else "",
            "estado": "programada" if current_block["fecha"] else "lista_espera",
            "asistencia": asistencia,
            "consultorio": "",
            "observacion": nota,
            "notas_adicionales": "",
            "bloque_titulo_raw": current_block["titulo_raw"],
        }
        rows_out.append(out)

        if not numero_doc or not telefono1 or not out["fecha_programada"]:
            review_out.append({**out, "motivo_revision": "dato_clave_faltante (documento/telefono/fecha)"})
        if asistencia == "revisar_color":
            review_out.append({**out, "motivo_revision": "color de fila no reconocido (ni blanco ni verde) para una fecha pasada -- revisar a mano"})


# Pedido explicito del usuario 2026-11-16: la hoja mezcla solicitudes de
# 2025 y 2026 ("eso esta muy variado") -- las de 2025 ya deberian estar
# resueltas de una forma u otra (agendadas hace meses, o la persona ya no
# sigue esperando), asi que solo cuenta como lista de espera REAL la
# solicitud recibida desde este corte.
WAITLIST_CUTOFF = datetime.date(2026, 1, 1)


def process_urodinamia_waitlist(wb, rows_out, review_out):
    ws = wb["LISTADO PC URODINAMIAS"]
    for row_idx in range(2, ws.max_row + 1):
        nombre = ws.cell(row=row_idx, column=3).value
        if not clean_text(nombre):
            continue

        clasificacion = fill_classification(ws.cell(row=row_idx, column=2))
        if clasificacion in ("ya_agendado", "convenio_terminado"):
            continue  # ya no esta en lista de espera -- ver regla de color arriba

        fecha_solicitud = ws.cell(row=row_idx, column=1).value
        fecha_solicitud_date = (
            fecha_solicitud.date()
            if isinstance(fecha_solicitud, datetime.datetime)
            else fecha_solicitud if isinstance(fecha_solicitud, datetime.date) else None
        )
        if fecha_solicitud_date and fecha_solicitud_date < WAITLIST_CUTOFF:
            continue  # solicitud de 2025 -- fuera del corte, ver comentario arriba
        numero = ws.cell(row=row_idx, column=2).value
        nota_llamadas = clean_text(ws.cell(row=row_idx, column=6).value)
        telefono_raw = ws.cell(row=row_idx, column=13).value
        procedimiento = ws.cell(row=row_idx, column=15).value

        telefono1, telefono2, telefono_extra = split_phones(telefono_raw)
        numero_doc = only_digits(numero)
        servicio_normalizado, servicio_raw = normalize_service(procedimiento)

        notas = []
        if nota_llamadas:
            notas.append(nota_llamadas)
        if isinstance(fecha_solicitud, (datetime.datetime, datetime.date)):
            notas.append(f"[Solicitud recibida: {fecha_solicitud.date().isoformat()}]")

        out = {
            "fuente_hoja": "LISTADO PC URODINAMIAS",
            "fuente_fila": row_idx,
            "tipo_registro": "lista_espera_urodinamia",
            "tipo_documento": "CC",
            "numero_documento": numero_doc,
            "nombre": clean_text(nombre),
            "telefono_1": telefono1,
            "telefono_2": telefono2,
            "telefono_extra": telefono_extra,
            "entidad_eps": normalize_eps(ws.cell(row=row_idx, column=7).value),
            "especialidad": "Urologia",
            "profesional": "María",
            "servicio_normalizado": servicio_normalizado,
            "servicio_raw": servicio_raw,
            "fecha_programada": "",
            "fecha_confianza": "sin_fecha",
            "hora_programada": "",
            "estado": "lista_espera",
            "asistencia": "",
            "fecha_solicitud": fecha_solicitud_date.isoformat() if fecha_solicitud_date else "",
            "consultorio": "",
            "observacion": "",
            "notas_adicionales": " | ".join(notas),
            "bloque_titulo_raw": "",
        }
        rows_out.append(out)

        if not numero_doc or not telefono1:
            review_out.append({**out, "motivo_revision": "dato_clave_faltante (documento/telefono)"})
        if clasificacion == "otro_color":
            review_out.append({
                **out,
                "motivo_revision": "color de fila no reconocido (ni blanco ni morado ni azul claro) -- revisar a mano",
            })


FIELDNAMES = [
    "fuente_hoja", "fuente_fila", "tipo_registro", "tipo_documento", "numero_documento",
    "nombre", "telefono_1", "telefono_2", "telefono_extra", "entidad_eps", "especialidad",
    "profesional", "servicio_normalizado", "servicio_raw", "fecha_programada",
    "fecha_confianza", "hora_programada", "estado", "asistencia", "fecha_solicitud",
    "consultorio", "observacion", "notas_adicionales", "bloque_titulo_raw",
]


def main():
    rows_out = []
    review_out = []

    wb_agendas = openpyxl.load_workbook(SOURCE_AGENDAS, data_only=True)
    process_master_sheet(wb_agendas, "CONSULTAS UROLOGIA ", "consulta_maestro", rows_out, review_out)
    process_master_sheet(wb_agendas, "PROCEDIMIENTOS UROLOGIA ", "procedimiento_maestro", rows_out, review_out)
    for sheet_name, doctor in DOCTOR_SHEETS.items():
        process_doctor_sheet(wb_agendas, sheet_name, doctor, rows_out, review_out)

    wb_particulares = openpyxl.load_workbook(SOURCE_PARTICULARES, data_only=True)
    for sheet_name, doctor in PARTICULAR_SHEETS.items():
        process_particular_sheet(wb_particulares, sheet_name, doctor, rows_out, review_out)

    # PENDIENTES -- lista de espera de ginecologia (particular y EPS mezcladas,
    # ver CONTEXTO_NEGOCIO_FASE2.md "Ronda 6"). Mismo caos de columnas que
    # CONSULTAS UROLOGIA (FECHA sin fecha confiable, doctor mencionado ahi
    # mismo) pero con encabezados "CONTACTO"/"ENTIDAD" en vez de
    # "TELEFONOS"/"EPS", y SIN columna de procedimiento confiable -- se
    # asume "Consulta" (lo que es casi siempre) en vez de perder la fila.
    process_master_sheet(
        wb_particulares, "PENDIENTES", "pendiente_ginecologia", rows_out, review_out,
        column_aliases={"TELEFONOS": "CONTACTO", "EPS": "ENTIDAD"},
        default_especialidad="Ginecologia", default_profesional="Dra. Cano",
        default_servicio="Consulta",
    )

    wb_urodinamia = openpyxl.load_workbook(SOURCE_URODINAMIA_WAITLIST, data_only=True)
    process_urodinamia_agenda(wb_urodinamia, rows_out, review_out)
    process_urodinamia_waitlist(wb_urodinamia, rows_out, review_out)

    # Servicio irreconocible ("Otro") suele ser una columna corrida en el
    # Excel original (ej. la EPS quedo pegada en la celda de PROCEDIMIENTO)
    # -- siempre se manda a revision humana, nunca se adivina.
    ya_marcadas = {(r["fuente_hoja"], r["fuente_fila"]) for r in review_out}
    for r in rows_out:
        if r["servicio_normalizado"] == "Otro" and (r["fuente_hoja"], r["fuente_fila"]) not in ya_marcadas:
            review_out.append({**r, "motivo_revision": f"procedimiento no reconocido: '{r['servicio_raw']}'"})

    out_csv = OUT_DIR / "agendas_normalizadas.csv"
    with out_csv.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(rows_out)

    review_csv = OUT_DIR / "revision_requerida.csv"
    with review_csv.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES + ["motivo_revision"])
        writer.writeheader()
        writer.writerows(review_out)

    total = len(rows_out)
    programadas = sum(1 for r in rows_out if r["estado"] == "programada")
    lista_espera = total - programadas
    sin_profesional = sum(1 for r in rows_out if not r["profesional"])
    por_tipo = {}
    for r in rows_out:
        por_tipo[r["tipo_registro"]] = por_tipo.get(r["tipo_registro"], 0) + 1

    print(f"Filas normalizadas: {total}")
    for tipo, count in sorted(por_tipo.items()):
        print(f"  {tipo}: {count}")
    print(f"  Programadas:   {programadas}")
    print(f"  Lista espera:  {lista_espera}")
    print(f"  Sin profesional resuelto: {sin_profesional}")
    print(f"Filas marcadas para revision humana: {len(review_out)}")
    print(f"-> {out_csv}")
    print(f"-> {review_csv}")


if __name__ == "__main__":
    main()
