#!/usr/bin/env python3
"""Driver: PARTICULARES 2026.xlsx -> normalizado_particulares.csv.

Solo 3 de las 14 hojas son citas (dialecto HORA/CEDULA/NOMBRE/TELEFONO/EPS/
PROCEDIMIENTO/VALOR, ya soportado por agendas_parser_lib) + PENDIENTES
(lista de espera -- fecha real de solicitud, igual dialecto que CONSULTAS
UROLOGIA). Las demas 10 hojas (copagos Medplus/Sura, pagos/abonos de
terapias, citologias, telefonos, cuentas bancarias) quedan fuera a
decision explicita del usuario: no tienen hora/fecha de cita, no afectan
la correccion de created_at que es el objetivo central de este proyecto."""
import sys
from pathlib import Path

from agendas_parser_lib import run

BLOCK_SHEETS = {
    'AGENDA DRA CANO': 'DRA CANO',
    'AGENDA  DR. CORRALES ': 'DR CORRALES',
    # Varias terapeutas distintas (MAYRA/MAIRA/CATHERINE) sin forma de saber
    # cual atendio cada cita -- el usuario pidio un profesional generico
    # "TERAPIAS" (nuevo, a crear en fase 3) en vez de intentar separarlas.
    'FECHAS TERCARTERAPIA': 'TERAPIAS',
}
WAITLIST_SHEETS = ['PENDIENTES']

if __name__ == '__main__':
    source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        'data_imports/calendario_agendas_dr_corrales_2026/source/citas_docs/citas_batch_4/PARTICULARES 2026.xlsx'
    )
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(
        'data_imports/calendario_agendas_dr_corrales_2026/normalizado_particulares.csv'
    )
    run(source_path, out_path, BLOCK_SHEETS, WAITLIST_SHEETS)
