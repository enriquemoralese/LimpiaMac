# LimpiaMac

App para Mac que encuentra lo que ocupa espacio sin servir y lo manda a la Papelera solo si tú lo apruebas.

Funciona en Macs con chip Apple (M1 o más nuevo) y macOS 14 o más nuevo.

## Descargar

1. Baja **[LimpiaMac.zip](https://github.com/enriquemoralese/LimpiaMac/releases/latest/download/LimpiaMac.zip)** y ábrelo.
2. Arrastra **LimpiaMac** a tu carpeta **Aplicaciones**.
3. La primera vez, haz **clic derecho › Abrir** y confirma. Si macOS no te deja, ve a **Ajustes del Sistema › Privacidad y seguridad** y presiona **Abrir de todos modos**.
4. Dale permiso para revisar todo el disco: en **Ajustes del Sistema › Privacidad y seguridad › Acceso total al disco**, agrega LimpiaMac. Sin esto, el escaneo sale incompleto.

macOS muestra el aviso del paso 3 porque la app no está firmada con una cuenta de desarrollador de Apple. Es normal en apps fuera de la App Store.

## Usar

1. Presiona **Escanear**.
2. Revisa cada categoría. Haz clic en un archivo para verlo en grande.
3. Marca lo que quieras borrar y presiona **Mover a la Papelera**.

Nada se borra de forma definitiva hasta que vacías la Papelera.

## Proteger tus carpetas

En **LimpiaMac › Ajustes** (⌘,) agrega las carpetas que la app nunca debe tocar, como tus documentos importantes o tus proyectos. Hazlo antes de tu primer escaneo.

## Compilarla tú mismo

Necesitas las herramientas de Apple (`xcode-select --install`). En Terminal:

```
git clone https://github.com/enriquemoralese/LimpiaMac.git
cd LimpiaMac
./empaquetar.sh
mv LimpiaMac.app /Applications/
```
