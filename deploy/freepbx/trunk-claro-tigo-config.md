# Configuracion Trunk PSTN (Claro / Tigo) — ProCall Chat

> Aplica tanto para Claro como para Tigo Business Colombia.
> Los parámetros específicos los entrega el proveedor al contratar la troncal SIP.

---

## Datos requeridos del proveedor (rellenar con Claro o Tigo)

| Campo | Claro | Tigo |
|---|---|---|
| IP / hostname SBC | [PENDIENTE] | [PENDIENTE] — referencia: `tbd-prd-co.tigocloud.net` |
| Puerto SIP | 5060 | 5060 (o 5061 con TLS) |
| Usuario SIP trunk | [PENDIENTE] | [PENDIENTE] |
| Password SIP trunk | [PENDIENTE] | [PENDIENTE] |
| DID / número asignado | [PENDIENTE] | [PENDIENTE] |
| Tipo de autenticación | IP o registro | IP o registro |
| Codecs soportados | alaw (G.711a) | alaw / ulaw |

> Tigo no publica su documentación técnica en abierto. Solicitar al comercial:
> - Ficha técnica de troncal SIP
> - IP del SBC + rangos IP autorizados (para whitelist firewall/FreePBX)
> - Método de autenticación preferido (IP-based vs registration)

---

## FreePBX — Trunk SIP (chan_pjsip)

`Connectivity > Trunks > Add Trunk > SIP (chan_pjsip)`

```
Trunk Name: pstn-claro   (o pstn-tigo)
```

**PJSIP Settings — General:**
```
Username:     [USUARIO_PROVEEDOR]
Secret:       [PASSWORD_PROVEEDOR]
SIP Server:   [IP_SBC_PROVEEDOR]
SIP Server Port: 5060
```

**PJSIP Settings — Advanced:**
```
From Domain:  [IP_SBC_PROVEEDOR]
From User:    [USUARIO_PROVEEDOR]
```

**PEER Details (chan_sip legacy — solo si el proveedor no soporta pjsip):**
```ini
disallow=all
allow=alaw
type=peer
host=[IP_SBC_PROVEEDOR]
username=[USUARIO_PROVEEDOR]
secret=[PASSWORD_PROVEEDOR]
insecure=port,invite
qualify=yes
dtmfmode=rfc2833
canreinvite=no
```

Maximum Channels: 5 (ajustar según contrato)

---

## FreePBX — Inbound Route

`Connectivity > Inbound Routes > Add`

```
DID Number:   [NUMERO_DID]
Destination:  Custom Applications > stasis-routing
```

---

## FreePBX — Outbound Route

`Connectivity > Outbound Routes > Add`

```
Route Name:     colombia-nacional
Trunk Sequence: pstn-claro (o pstn-tigo)
```

**Dial Patterns:**
```
3XXXXXXXXX    (celulares Colombia — 10 dígitos)
NXXXXXXXXX    (fijos con indicativo de ciudad — 10 dígitos)
0XXXXXXXXXX   (larga distancia nacional — 11 dígitos)
```

> Colombia unificó a 10 dígitos en 2024. Los fijos Bogotá son `601XXXXXXX`.

---

## Dialplan manual (si no se usa FreePBX GUI)

En `/etc/asterisk/extensions_custom.conf`:

```ini
[stasis-routing]
exten => _X.,1,NoOp(Llamada entrante PSTN: ${CALLERID(num)} -> ${EXTEN})
 same => n,Stasis(stasis-routing)
 same => n,Hangup()
```

---

## Firewall / Red

- Abrir puerto **5060 UDP** (SIP) hacia la IP del SBC del proveedor
- Abrir rango **10000–20000 UDP** (RTP audio) desde/hacia el SBC
- Si el proveedor pide autenticación por IP: confirmar IP pública del servidor FreePBX y enviarla al comercial

---

## Aplicar cambios en Asterisk

```bash
# Después de cada cambio en FreePBX GUI → Apply Config
asterisk -rx "module reload res_pjsip.so"

# Verificar registro del trunk
asterisk -rx "pjsip show registrations"
asterisk -rx "pjsip show endpoints"

# Debug en tiempo real
asterisk -rx "pjsip set logger on"
asterisk -rvvv
```

---

## Referencias

- Tigo Business Colombia — Troncal SIP: https://tbd-prd-co.tigocloud.net/b2b/troncal-sip
- Tigo Ayuda — E1/SIPtrunk (Nicaragua, misma arquitectura técnica): https://ayuda.tigo.com.ni/hc/es/articles/16764327056531
- Configurar SIP Trunk en Asterisk: https://siptrunkhub.es/configurar-el-sip-trunk-en-asterisk/
