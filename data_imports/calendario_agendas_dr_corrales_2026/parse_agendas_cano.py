#!/usr/bin/env python3
"""Driver: AGENDAS DRA CANO 2026.xlsx -> normalizado_cano.csv.

De las 78 hojas del archivo, SOLO 5 son datos reales de 2026 -- las otras
73 son basura historica confirmada (2014/2015/2018, o plantillas vacias sin
pacientes). Confirmado fila por fila con el usuario antes de procesar, ver
SESION_2026-11-24_POST_IMPORT_FIXES.md / historial de esta sesion."""
import sys
from pathlib import Path

from agendas_parser_lib import run

BLOCK_SHEETS = {
    'DRA CANO FOMAG  ': 'DRA CANO',
    'DR ESPITIA ': 'DR ESPITIA',  # nuevo profesional a crear en fase 3, confirmado con el usuario
    'PC MORCELACION': 'DR ESPITIA',
}
WAITLIST_SHEETS = ['CONSULTAS GINECOLOGIA ', 'PROCEDIMIENTOS GINECOLOGIA ']

if __name__ == '__main__':
    source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        'data_imports/calendario_agendas_dr_corrales_2026/source/citas_docs/citas_batch_4/AGENDAS DRA CANO 2026.xlsx'
    )
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(
        'data_imports/calendario_agendas_dr_corrales_2026/normalizado_cano.csv'
    )
    run(source_path, out_path, BLOCK_SHEETS, WAITLIST_SHEETS)
