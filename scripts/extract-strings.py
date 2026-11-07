#!/usr/bin/env python3
"""Lista (ou sincroniza) as strings localizaveis extraidas pelo compilador.

Uso:
  scripts/extract-strings.py list                 # imprime as chaves unicas do build Debug
  scripts/extract-strings.py sync                 # adiciona ao Localizable.xcstrings as chaves novas (sem traducao)
  scripts/extract-strings.py check                # falha se faltar pt-BR ou houver chave nova fora do catalogo
O build precisa existir: xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug -derivedDataPath build build
"""
import glob
import json
import os
import sys

CATALOG = "Ice/Resources/Localizable.xcstrings"


def extracted_keys():
    """Chaves extraidas pelo compilador. Para cada arquivo-fonte vale o .stringsdata
    mais recente (builds Debug e Release antigos nao contam)."""
    pattern = "build/Build/Intermediates.noindex/Ice.build/*/Ice.build/Objects-normal/*/*.stringsdata"
    newest = {}
    for path in glob.glob(pattern):
        data = json.load(open(path))
        source = data.get("source", "")
        if "/Ice/" not in source and "/Shared/" not in source:
            continue
        mtime = os.path.getmtime(path)
        if source not in newest or mtime > newest[source][0]:
            newest[source] = (mtime, data)
    keys = {}
    for source, (_, data) in newest.items():
        for entry in data.get("tables", {}).get("Localizable", []):
            keys.setdefault(entry["key"], source.split("/Trincano/")[-1])
    return keys


def load_catalog():
    return json.load(open(CATALOG))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    keys = extracted_keys()
    if not keys:
        print("ERRO: nenhuma string extraida; faca o build antes (xcodebuild ... build).")
        sys.exit(2)
    if mode == "list":
        for key in sorted(keys):
            print(repr(key), "<-", keys[key])
        return
    catalog = load_catalog()
    strings = catalog["strings"]
    if mode == "sync":
        for key in keys:
            strings.setdefault(key, {"extractionState": "extracted_with_value"})
        json.dump(catalog, open(CATALOG, "w"), ensure_ascii=False, indent=2, sort_keys=True)
        print(f"{len(keys)} chaves; catalogo com {len(strings)}")
        return
    missing = [k for k in keys if k not in strings]
    untranslated = [k for k, v in strings.items()
                    if "pt-BR" not in v.get("localizations", {}) and not v.get("shouldTranslate") is False]
    for k in missing:
        print("FALTA NO CATALOGO:", repr(k))
    for k in untranslated:
        print("SEM pt-BR:", repr(k))
    sys.exit(1 if missing or untranslated else 0)


main()
