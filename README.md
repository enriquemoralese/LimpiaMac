# LimpiaMac

App nativa (SwiftUI, macOS 14+) para encontrar lo que ocupa espacio sin servir: cachés, instaladores, archivos grandes, archivos viejos o sin abrir, carpetas dormidas y duplicados. Solo mueve a la Papelera lo que tú confirmas.

## Uso
```
swift test            # pruebas sobre carpetas ficticias
./empaquetar.sh       # arma LimpiaMac.app
open LimpiaMac.app
```
Para un escaneo completo, agrega `LimpiaMac.app` en Ajustes del Sistema › Privacidad y seguridad › Acceso total al disco. Con firma ad hoc, cada vez que recompilas macOS puede pedir el permiso de nuevo.

## Reglas de seguridad
- El escaneo es de solo lectura. Lo único que modifica el disco es `Papelera.mover`, que usa la Papelera de macOS y vuelve a revisar las reglas antes de mover.
- Zonas protegidas en `Sources/LimpiaNucleo/Reglas.swift` (Useful_docs, FL Studio, beats, carpetas de trabajo) más las que agregues en Ajustes.
- Nombres sensibles (INE, RFC, estados de cuenta, contraseñas, llaves...) llevan candado, nunca se preseleccionan y piden confirmación extra.
- Registro de lo movido: `~/Library/Application Support/LimpiaMac/historial.json`.
