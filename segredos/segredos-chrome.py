# -*- coding: utf-8 -*-
"""
Exporta e reimporta os segredos do Chrome que a formatacao destroi.

  python segredos-chrome.py exportar            > segredos.json
  python segredos-chrome.py importar            < segredos.json

Por que isto existe: o Chrome guarda em "Local State" uma chave AES-256-GCM selada
pela DPAPI. A DPAPI abre essa chave com a master key do usuario, derivada da senha e
do SID da conta. Formatar cria SID novo e master key nova, entao a chave selada vira
ilegivel e as senhas salvas somem junto. A pasta do perfil sobreviver em D: nao ajuda:
volta a caixa, nao volta o que abre a caixa.

A saida e JSON EM CLARO. Nunca gravar em disco sem cifrar: os scripts .ps1 ao lado
canalizam por age, com a chave publica do Alexandre, e a chave privada fica no pendrive.

Limite conhecido: o Chrome 127+ cifra cookies com App-Bound Encryption, marcados v20,
presa a identidade do aplicativo e nao so a DPAPI. Esses nao saem por aqui e o script
os conta como "ignorados". Senhas continuam em v10/v11 e saem normalmente.

O Chrome precisa estar FECHADO: ele mantem os SQLite abertos com lock exclusivo.
"""

import base64
import ctypes
import ctypes.wintypes
import json
import os
import shutil
import sqlite3
import sys
import tempfile

PERFIL = os.path.join(
    os.environ.get('LOCALAPPDATA', ''), 'Google', 'Chrome', 'User Data'
)
ALVOS = [
    # (arquivo relativo ao perfil, tabela, coluna cifrada)
    (os.path.join('Default', 'Login Data'), 'logins', 'password_value'),
    (os.path.join('Default', 'Cookies'), 'cookies', 'encrypted_value'),
]


class DATA_BLOB(ctypes.Structure):
    _fields_ = [
        ('cbData', ctypes.wintypes.DWORD),
        ('pbData', ctypes.POINTER(ctypes.c_char)),
    ]


def _blob(data):
    buf = ctypes.create_string_buffer(data, len(data))
    return DATA_BLOB(len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_char)))


def dpapi_abrir(data):
    """CryptUnprotectData: so funciona na conta que selou o dado."""
    entrada, saida = _blob(data), DATA_BLOB()
    ok = ctypes.windll.crypt32.CryptUnprotectData(
        ctypes.byref(entrada), None, None, None, None, 0, ctypes.byref(saida)
    )
    if not ok:
        raise OSError('CryptUnprotectData falhou (erro %d). A conta atual nao selou este dado.'
                      % ctypes.GetLastError())
    try:
        return ctypes.string_at(saida.pbData, saida.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(saida.pbData)


def chave_do_perfil(perfil):
    """Le a chave AES do Local State e a abre pela DPAPI."""
    caminho = os.path.join(perfil, 'Local State')
    with open(caminho, encoding='utf-8') as f:
        estado = json.load(f)
    b64 = estado.get('os_crypt', {}).get('encrypted_key')
    if not b64:
        raise SystemExit('os_crypt.encrypted_key ausente em %s' % caminho)
    bruto = base64.b64decode(b64)
    if not bruto.startswith(b'DPAPI'):
        raise SystemExit('encrypted_key sem o prefixo DPAPI; formato inesperado')
    return dpapi_abrir(bruto[5:])


def decifrar(valor, chave):
    """Devolve (texto, motivo). texto e None quando nao da para decifrar."""
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    if not valor:
        return '', None
    marca = valor[:3]
    if marca == b'v20':
        return None, 'v20 (App-Bound Encryption; fora do alcance da DPAPI)'
    if marca in (b'v10', b'v11'):
        nonce, resto = valor[3:15], valor[15:]
        try:
            return AESGCM(chave).decrypt(nonce, resto, None).decode('utf-8', 'replace'), None
        except Exception as e:
            return None, 'AES-GCM falhou: %s' % e
    try:
        return dpapi_abrir(valor).decode('utf-8', 'replace'), None
    except Exception as e:
        return None, 'DPAPI direto falhou: %s' % e


def cifrar(texto, chave):
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    nonce = os.urandom(12)
    return b'v10' + nonce + AESGCM(chave).encrypt(nonce, texto.encode('utf-8'), None)


def _copia_destravada(origem):
    """O Chrome mantem lock exclusivo; trabalha-se sobre uma copia."""
    destino = os.path.join(tempfile.mkdtemp(prefix='segredos-'), os.path.basename(origem))
    shutil.copy2(origem, destino)
    return destino


def exportar(perfil):
    chave = chave_do_perfil(perfil)
    saida = {'perfil': perfil, 'tabelas': {}}
    resumo = []
    for rel, tabela, coluna in ALVOS:
        caminho = os.path.join(perfil, rel)
        if not os.path.exists(caminho):
            resumo.append('%s: arquivo nao existe, pulado' % rel)
            continue
        copia = _copia_destravada(caminho)
        con = sqlite3.connect(copia)
        con.row_factory = sqlite3.Row
        try:
            colunas = [c[1] for c in con.execute('PRAGMA table_info(%s)' % tabela)]
            if coluna not in colunas:
                resumo.append('%s: tabela %s sem coluna %s, pulado' % (rel, tabela, coluna))
                continue
            linhas, ok, ignorados = [], 0, 0
            for linha in con.execute('SELECT * FROM %s' % tabela):
                d = {k: linha[k] for k in colunas}
                texto, motivo = decifrar(d.get(coluna) or b'', chave)
                if texto is None:
                    ignorados += 1
                    continue
                d.pop(coluna, None)
                d['__claro__'] = texto
                linhas.append(d)
                ok += 1
            saida['tabelas'][rel] = {'tabela': tabela, 'coluna': coluna,
                                     'colunas': colunas, 'linhas': linhas}
            resumo.append('%s: %d exportados, %d ignorados' % (rel, ok, ignorados))
        finally:
            con.close()
            shutil.rmtree(os.path.dirname(copia), ignore_errors=True)
    for l in resumo:
        print(l, file=sys.stderr)
    json.dump(saida, sys.stdout, ensure_ascii=False)


def importar(perfil):
    dados = json.load(sys.stdin)
    chave = chave_do_perfil(perfil)   # chave NOVA, da conta atual
    for rel, bloco in dados.get('tabelas', {}).items():
        caminho = os.path.join(perfil, rel)
        if not os.path.exists(caminho):
            print('%s: nao existe no perfil novo; abra o Chrome uma vez e repita' % rel,
                  file=sys.stderr)
            continue
        tabela, coluna = bloco['tabela'], bloco['coluna']
        con = sqlite3.connect(caminho)
        try:
            existentes = [c[1] for c in con.execute('PRAGMA table_info(%s)' % tabela)]
            gravados = 0
            for d in bloco['linhas']:
                texto = d.pop('__claro__', '')
                d[coluna] = cifrar(texto, chave)
                campos = [c for c in existentes if c in d]
                marcas = ','.join('?' for _ in campos)
                sql = 'INSERT OR REPLACE INTO %s (%s) VALUES (%s)' % (
                    tabela, ','.join('"%s"' % c for c in campos), marcas)
                try:
                    con.execute(sql, [d[c] for c in campos])
                    gravados += 1
                except sqlite3.Error as e:
                    print('  linha recusada em %s: %s' % (tabela, e), file=sys.stderr)
            con.commit()
            print('%s: %d gravados' % (rel, gravados), file=sys.stderr)
        finally:
            con.close()


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ('exportar', 'importar'):
        raise SystemExit(__doc__)
    perfil = sys.argv[2] if len(sys.argv) > 2 else PERFIL
    if not os.path.isdir(perfil):
        raise SystemExit('perfil do Chrome nao encontrado: %s' % perfil)
    (exportar if sys.argv[1] == 'exportar' else importar)(perfil)


if __name__ == '__main__':
    main()
