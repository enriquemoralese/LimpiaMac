#!/bin/bash
# Corre las pruebas de la interfaz real (Sources/iClear/PruebasUI.swift) sobre la app empaquetada,
# la misma que se entrega. Escanea tu carpeta en modo de solo lectura: no mueve ni borra nada.
# Se abre con `open` para que macOS la ponga al frente (si no, los clics simulados no llegan).
# Termina con 0 si todo pasó. Deja la salida completa en .build/pruebas_ui.log.
set -uo pipefail
cd "$(dirname "$0")/.."

./empaquetar.sh > /dev/null || { echo "No se pudo empaquetar"; exit 1; }
osascript -e 'quit app "iClear"' 2>/dev/null

LOG="$(pwd)/.build/pruebas_ui.log"
rm -f "$LOG"
# Con un argumento corre solo esa prueba, por ejemplo: Scripts/pruebas_ui.sh reproductor
open -W -n --env ICLEAR_PRUEBAS_UI=1 --env "ICLEAR_PRUEBAS_SOLO=${1:-}" --stdout "$LOG" --stderr "$LOG" ./iClear.app

grep -E "^PRUEBA" "$LOG"
avisos=$(grep -c "reentrant operation" "$LOG")
echo "Avisos de macOS 'reentrant operation in NSTableView': $avisos"
[ "$avisos" -eq 0 ] || { echo "Regresó el aviso de reentrada (ver comentario en Principal.swift)"; exit 1; }
if ! grep -q "^PRUEBA FIN" "$LOG"; then
    echo "La app terminó sin llegar al final (¿tronó?). Revisa $LOG"
    exit 1
fi
grep -q "^PRUEBA FIN fallas=0" "$LOG"
