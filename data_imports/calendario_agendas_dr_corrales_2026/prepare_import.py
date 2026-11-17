#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Segunda fase de la normalizacion: convierte agendas_normalizadas.csv (una
fila por cada fila original del Excel, 2275 filas) en los 4 archivos listos
para cargar que el importador de Rails consume:

  contacts.csv                 -- 1 fila por paciente (deduplicado por
                                   numero_documento, con el mejor dato
                                   disponible entre todas sus apariciones).
  appointments.csv              -- 1 fila por cita REAL (con profesional
                                   resuelto). Elimina los duplicados entre
                                   las hojas maestras y las hojas por-doctor
                                   (ver "Hallazgo: filas duplicadas" abajo).
  waitlist.csv                  -- filas sin fecha pero CON profesional
                                   resuelto -> van a lista de espera real
                                   (pending), SOLO si esa persona no tiene
                                   ya una cita real con ese profesional en
                                   ningun lado del Excel (ver
                                   waitlist_fulfilled.csv si SI la tiene).
  waitlist_fulfilled.csv        -- igual que arriba, pero la persona YA
                                   tiene una cita real (en otra hoja) con
                                   ese profesional -- no sigue esperando.
                                   Se importa igual (import_to_local.rb la
                                   crea con status "fulfilled" y la fecha
                                   de solicitud como created_at) para poder
                                   calcular la estadistica real de "cuanto
                                   tiempo desde que se registro hasta que
                                   tuvo la cita", pedida explicitamente por
                                   el usuario 2026-11-17 -- sin esto esa
                                   comparacion se perdia (la fila se
                                   descartaba del todo o quedaba como
                                   pendiente aunque ya no lo estuviera).
  pendientes_sin_profesional.csv -- filas (programadas o no) sin profesional
                                   resuelto en ningun lado del Excel. NO se
                                   importan: no hay campo valido para
                                   asignarlas a nadie sin inventar un dato
                                   que el archivo no tiene.

Uso: python3 prepare_import.py
"""
import csv
from collections import Counter, defaultdict
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent
SOURCE_CSV = OUT_DIR / "agendas_normalizadas.csv"

DEFAULT_TIME = "08:00"

CONTACTS_FIELDS = [
    "numero_documento", "tipo_documento", "nombre", "telefono_1", "telefono_2", "entidad_eps",
]
APPOINTMENTS_FIELDS = [
    "numero_documento", "profesional", "servicio_normalizado", "fecha_programada",
    "hora_programada", "hora_es_estimada", "asistencia", "consultorio", "notas",
    "fuente_hoja", "fuente_fila",
]
WAITLIST_FIELDS = [
    "numero_documento", "profesional", "servicio_normalizado", "fecha_solicitud", "notas",
    "fuente_hoja", "fuente_fila",
]
WAITLIST_FULFILLED_FIELDS = WAITLIST_FIELDS + ["fecha_cita_real"]


def load_rows():
    with SOURCE_CSV.open(encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def build_contacts(rows):
    """Un paciente puede aparecer en varias hojas con pequeñas variaciones
    (acentos, espacios, EPS distinta si cambio de aseguradora) -- se agrupa
    por numero_documento y se elige el dato mas frecuente de cada campo."""
    by_doc = defaultdict(list)
    for r in rows:
        if r["numero_documento"]:
            by_doc[r["numero_documento"]].append(r)

    contacts = []
    for doc, group in by_doc.items():
        names = Counter(g["nombre"].strip() for g in group if g["nombre"].strip())
        if not names:
            # Fila(s) basura del Excel original: numero_documento presente
            # (a veces ni siquiera es un documento real, ej. un fragmento de
            # fecha mal cortado) pero SIN nombre en ninguna aparicion -- no
            # hay con que crear un contacto real, se descarta en vez de
            # crear uno vacio que rompe la carga.
            continue
        phones1 = Counter(g["telefono_1"] for g in group if g["telefono_1"])
        epss = Counter(g["entidad_eps"] for g in group if g["entidad_eps"] and g["entidad_eps"] != "UROLOGIA")
        tipos = Counter(g["tipo_documento"] for g in group if g["tipo_documento"])

        telefono_1 = phones1.most_common(1)[0][0] if phones1 else ""
        phones2 = Counter(
            g["telefono_2"] for g in group if g["telefono_2"] and g["telefono_2"] != telefono_1
        )
        telefono_2 = phones2.most_common(1)[0][0] if phones2 else ""

        contacts.append({
            "numero_documento": doc,
            "tipo_documento": (tipos.most_common(1)[0][0] if tipos else "CC").lower(),
            "nombre": names.most_common(1)[0][0] if names else "",
            "telefono_1": telefono_1,
            "telefono_2": telefono_2,
            "entidad_eps": epss.most_common(1)[0][0] if epss else "",
        })
    return contacts


def dedupe_key(row):
    return (row["numero_documento"], row["fecha_programada"])


def build_schedule_rows(rows):
    """Separa en 3 grupos: citas reales (con profesional + fecha),
    lista de espera real (con profesional, sin fecha) y pendientes (sin
    profesional en ningun lado). Tambien fusiona los duplicados
    master-sheet/doctor-sheet (ver README punto 'Hallazgo: duplicados') Y
    los duplicados ENTRE hojas "por profesional" (ej. un paciente de Los
    Rosales aparece tanto en 'AGENDAS' como en 'CONS ROSALES', o un
    particular aparece tanto en 'AGENDAS' como en 'AGENDA DR. CORRALES' --
    son reportes distintos del MISMO cupo, no dos citas; ver
    CONTEXTO_NEGOCIO_FASE2.md, confirmado 90 colisiones reales)."""
    doctor_rows = [r for r in rows if r["tipo_registro"] in ("agenda_profesional", "agenda_particular")]
    master_rows = [r for r in rows if r["tipo_registro"] not in ("agenda_profesional", "agenda_particular")]

    # Dentro de las hojas "por profesional": si dos filas comparten
    # (documento,fecha), se queda solo la PRIMERA que aparezca con hora real
    # (no estimada) -- las demas se descartan como citas propias y su
    # hoja/EPS queda como nota fusionada en la que se mantuvo.
    merged_notes_by_key = defaultdict(list)
    seen_doctor_keys = {}
    deduped_doctor_rows = []
    for r in doctor_rows:
        key = dedupe_key(r)
        if not r["numero_documento"] or not r["fecha_programada"]:
            deduped_doctor_rows.append(r)
            continue
        kept = seen_doctor_keys.get(key)
        if kept is None:
            seen_doctor_keys[key] = r
            deduped_doctor_rows.append(r)
            continue
        # Ya hay una fila guardada para este (documento,fecha) -- esta es un
        # duplicado entre hojas, se fusiona como nota en vez de crear cita.
        merged_notes_by_key[key].append(
            f"[{r['fuente_hoja']}] EPS/entidad: {r['entidad_eps'] or '(sin dato)'}"
        )
        if not kept["hora_programada"] and r["hora_programada"]:
            # La version guardada no tenia hora real y esta si -- se usa esta.
            deduped_doctor_rows.remove(kept)
            deduped_doctor_rows.append(r)
            seen_doctor_keys[key] = r
    doctor_rows = deduped_doctor_rows

    # Observaciones de las hojas maestras que coinciden en (documento,fecha)
    # con una fila de hoja por-doctor -- se fusionan como nota en vez de
    # crear una cita duplicada.
    doctor_keys = {dedupe_key(r) for r in doctor_rows if r["numero_documento"] and r["fecha_programada"]}
    for r in master_rows:
        key = dedupe_key(r)
        if r["numero_documento"] and r["fecha_programada"] and key in doctor_keys and r["observacion"]:
            merged_notes_by_key[key].append(f"[{r['fuente_hoja']}] {r['observacion']}")

    appointments = []
    waitlist = []
    pendientes = []
    seen_master_keys = set()

    def build_notes(r, extra_from_merge=None):
        parts = []
        if r.get("observacion"):
            parts.append(r["observacion"])
        if r.get("notas_adicionales"):
            parts.append(r["notas_adicionales"])
        if extra_from_merge:
            parts.extend(extra_from_merge)
        parts.append(f"[Importado de Excel: {r['fuente_hoja']} fila {r['fuente_fila']}]")
        return " | ".join(parts)

    # (documento, profesional) -> fechas reales de cita con ese profesional,
    # de donde sea que vengan (doctor_rows o el ramo "programada" de
    # master_rows, llenado mas abajo antes de procesar el ramo
    # "lista_espera"). Sirve para decidir si alguien que aparece sin fecha
    # en una hoja de lista de espera YA esta agendado en otra -- pedido
    # explicito del usuario 2026-11-17: "que las personas en lista de
    # espera esten realmente ya agendadas o no lo esten".
    # Mismo filtro que el loop de abajo que arma `appointments` (documento +
    # servicio reconocido) -- bug real encontrado 2026-11-17: sin este
    # filtro, esta tabla contaba fechas de filas con servicio "Otro" que
    # NUNCA se crean como Calendario::Appointment, asi que el importador de
    # Rails encontraba la fecha "cumplida" pero ningun Appointment real con
    # que enlazarla (fulfilled_by_appointment_id quedaba en nil).
    real_dates_by_doc_prof = defaultdict(list)
    for r in doctor_rows:
        if r["numero_documento"] and r["fecha_programada"] and r["servicio_normalizado"] and r["servicio_normalizado"] != "Otro":
            real_dates_by_doc_prof[(r["numero_documento"], r["profesional"])].append(r["fecha_programada"])

    for r in doctor_rows:
        if not r["numero_documento"] or not r["servicio_normalizado"] or r["servicio_normalizado"] == "Otro":
            pendientes.append({**r, "motivo": "sin_documento_o_sin_servicio"})
            continue
        key = dedupe_key(r)
        appointments.append({
            "numero_documento": r["numero_documento"],
            "profesional": r["profesional"],
            "servicio_normalizado": r["servicio_normalizado"],
            "fecha_programada": r["fecha_programada"],
            "hora_programada": r["hora_programada"] or DEFAULT_TIME,
            "hora_es_estimada": "" if r["hora_programada"] else "si",
            "asistencia": r["asistencia"],
            "consultorio": r["consultorio"],
            "notas": build_notes(r, merged_notes_by_key.get(key)),
            "fuente_hoja": r["fuente_hoja"],
            "fuente_fila": r["fuente_fila"],
        })

    # Paso 1: SOLO el ramo "programada" -- hay que terminar de llenar
    # real_dates_by_doc_prof con estas citas ANTES de decidir el ramo
    # "lista_espera" de abajo (paso 2), porque una fila de lista de espera
    # de una hoja puede corresponder a una persona cuya cita real vive en
    # otra hoja maestra, no necesariamente en doctor_rows.
    for r in master_rows:
        if r["estado"] != "programada":
            continue
        if not r["numero_documento"] or not r["servicio_normalizado"] or r["servicio_normalizado"] == "Otro":
            pendientes.append({**r, "motivo": "sin_documento_o_sin_servicio"})
            continue
        key = dedupe_key(r)
        if not r["profesional"]:
            pendientes.append({**r, "motivo": "programada_sin_profesional"})
            continue
        if key in doctor_keys:
            continue  # ya se conto como cita en doctor_rows; su observacion ya se fusiono arriba.
        if key in seen_master_keys:
            continue  # duplicado dentro de la propia hoja maestra (mismo documento+fecha repetido).
        seen_master_keys.add(key)
        real_dates_by_doc_prof[(r["numero_documento"], r["profesional"])].append(r["fecha_programada"])
        appointments.append({
            "numero_documento": r["numero_documento"],
            "profesional": r["profesional"],
            "servicio_normalizado": r["servicio_normalizado"],
            "fecha_programada": r["fecha_programada"],
            "hora_programada": DEFAULT_TIME,
            "hora_es_estimada": "si",
            "asistencia": "",
            "consultorio": "",
            "notas": build_notes(r),
            "fuente_hoja": r["fuente_hoja"],
            "fuente_fila": r["fuente_fila"],
        })

    # Paso 2: el ramo "lista_espera", ya con real_dates_by_doc_prof completo.
    waitlist_fulfilled = []
    for r in master_rows:
        if r["estado"] == "programada":
            continue
        if not r["numero_documento"] or not r["servicio_normalizado"] or r["servicio_normalizado"] == "Otro":
            pendientes.append({**r, "motivo": "sin_documento_o_sin_servicio"})
            continue
        if not r["profesional"]:
            pendientes.append({**r, "motivo": "lista_espera_sin_profesional"})
            continue
        entry = {
            "numero_documento": r["numero_documento"],
            "profesional": r["profesional"],
            "servicio_normalizado": r["servicio_normalizado"],
            # Fecha en que el paciente pidio el cupo (columna "FECHA" de
            # las hojas maestras / columna 1 de LISTADO PC URODINAMIAS)
            # -- NO la fecha de esta carga. Confirmado por el usuario
            # 2026-11-17: sirve para que "dias esperando" y el orden
            # "mas antiguas primero" de la lista de espera reflejen la
            # realidad, no cuando corrio este importador.
            "fecha_solicitud": r["fecha_solicitud"],
            "notas": build_notes(r),
            "fuente_hoja": r["fuente_hoja"],
            "fuente_fila": r["fuente_fila"],
        }
        # Si esta persona YA tiene una cita real con ese MISMO profesional
        # (en cualquier hoja) en o despues de la fecha en que se registro,
        # no sigue esperando -- pedido explicito del usuario: "que las
        # personas en lista de espera esten realmente ya agendadas o no lo
        # esten". Se importa igual, pero como "cumplida" (fulfilled) con la
        # cita real mas cercana (la primera despues del registro), para
        # calcular cuanto tiempo paso entre que se registro y la cita
        # efectiva. Solo cuentan fechas >= fecha_solicitud -- una cita
        # ANTERIOR al registro es una visita vieja sin relacion con esta
        # solicitud puntual (bug real encontrado 2026-11-17: sin este
        # filtro salian "dias de espera" negativos).
        # Dos casos para decidir "cumplida" sin adivinar el tiempo de espera:
        # (a) con fecha_solicitud, solo cuentan fechas reales EN O DESPUES
        #     de esa fecha -- una cita anterior es una visita vieja sin
        #     relacion con esta solicitud puntual (bug real encontrado
        #     2026-11-17: sin este filtro salian "dias de espera" negativos).
        # (b) sin fecha_solicitud, no hay con que comparar "antes/despues",
        #     pero igual la persona ya NO esta esperando si existe
        #     cualquier cita real -- se marca cumplida de todas formas (la
        #     estadistica de dias de espera queda en 0/desconocida para
        #     esta fila en vez de en un numero inventado o negativo).
        real_dates = real_dates_by_doc_prof.get((r["numero_documento"], r["profesional"]), [])
        if r["fecha_solicitud"]:
            valid_dates = [d for d in real_dates if d >= r["fecha_solicitud"]]
        else:
            valid_dates = real_dates
        if valid_dates:
            entry["fecha_cita_real"] = min(valid_dates)
            waitlist_fulfilled.append(entry)
        else:
            waitlist.append(entry)

    return appointments, waitlist, waitlist_fulfilled, pendientes


def write_csv(path, fieldnames, rows):
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main():
    rows = load_rows()
    contacts = build_contacts(rows)
    appointments, waitlist, waitlist_fulfilled, pendientes = build_schedule_rows(rows)

    write_csv(OUT_DIR / "contacts.csv", CONTACTS_FIELDS, contacts)
    write_csv(OUT_DIR / "appointments.csv", APPOINTMENTS_FIELDS, appointments)
    write_csv(OUT_DIR / "waitlist.csv", WAITLIST_FIELDS, waitlist)
    write_csv(OUT_DIR / "waitlist_fulfilled.csv", WAITLIST_FULFILLED_FIELDS, waitlist_fulfilled)
    write_csv(
        OUT_DIR / "pendientes_sin_profesional.csv",
        list(rows[0].keys()) + ["motivo"] if rows else [],
        pendientes,
    )

    print(f"Contactos unicos:            {len(contacts)}")
    print(f"Citas a crear:               {len(appointments)}")
    print(f"Lista de espera (pendiente): {len(waitlist)}")
    print(f"Lista de espera (cumplida):  {len(waitlist_fulfilled)}")
    print(f"Pendientes (sin import):     {len(pendientes)}")
    print()
    print(f"-> {OUT_DIR / 'contacts.csv'}")
    print(f"-> {OUT_DIR / 'appointments.csv'}")
    print(f"-> {OUT_DIR / 'waitlist.csv'}")
    print(f"-> {OUT_DIR / 'waitlist_fulfilled.csv'}")
    print(f"-> {OUT_DIR / 'pendientes_sin_profesional.csv'}")


if __name__ == "__main__":
    main()
