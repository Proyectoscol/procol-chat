#!/usr/bin/env python3
"""Driver: AGENDAS DR CORRALES 2026.xlsx -> normalizado_corrales.csv.
Logica compartida con Cano en agendas_parser_lib.py -- ver ese archivo para
el detalle de como se parsean los dos dialectos de hoja."""
import sys
from pathlib import Path

from agendas_parser_lib import run

BLOCK_SHEETS = {
    'AGENDAS ': 'DR CORRALES',
    'DR DEVIA ': 'DR DEVIA',
    'DR VELEZ': 'DR VELEZ',
    'CONS ROSALES': 'DR CORRALES',  # titulos del bloque dicen "DR CORRALES"
    'DR GAVIRIA': 'DR GAVIRIA',
    'DRA ESPAÑA ': 'DRA ESPAÑA',
}
WAITLIST_SHEETS = ['CONSULTAS UROLOGIA ', 'PROCEDIMIENTOS UROLOGIA ']

if __name__ == '__main__':
    source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        'data_imports/calendario_agendas_dr_corrales_2026/source/citas_docs/citas_batch_4/AGENDAS DR CORRALES 2026.xlsx'
    )
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(
        'data_imports/calendario_agendas_dr_corrales_2026/normalizado_corrales.csv'
    )
    run(source_path, out_path, BLOCK_SHEETS, WAITLIST_SHEETS)
