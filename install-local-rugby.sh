#!/bin/bash

# Script para instalar localmente tu versión modificada de Rugby

# Directorio de instalación
INSTALL_DIR="$HOME/.rugby/clt"
mkdir -p "$INSTALL_DIR"

# Compilar Rugby en modo release
echo "🔨 Compilando Rugby en modo release..."
swift build -c release

# Verificar si la compilación fue exitosa
if [ ! -f ".build/release/rugby" ]; then
  echo "❌ Error: La compilación falló. No se pudo crear el binario."
  exit 1
fi

# Eliminar versión anterior si existe
if [ -f "$INSTALL_DIR/rugby" ]; then
  echo "🗑️  Eliminando versión anterior de Rugby..."
  rm "$INSTALL_DIR/rugby"
fi

# Copiar el binario
echo "📦 Instalando Rugby en $INSTALL_DIR..."
cp .build/release/rugby "$INSTALL_DIR/rugby"
chmod +x "$INSTALL_DIR/rugby"

# Agregar al PATH si no está (al principio para que tome precedencia)
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> ~/.zshrc
  echo "🔄 Se agregó $INSTALL_DIR al inicio de tu PATH. Reinicia tu terminal o ejecuta 'source ~/.zshrc'"
else
  # Si ya está en el PATH, moverlo al principio
  echo "🔄 Moviendo $INSTALL_DIR al inicio del PATH..."
  # Remover de la posición actual y agregar al principio
  sed -i '' "s|:$INSTALL_DIR||g" ~/.zshrc
  sed -i '' "s|$INSTALL_DIR:||g" ~/.zshrc
  echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> ~/.zshrc
fi

echo "✅ Rugby local instalado como 'rugby'"
echo "📋 Puedes ejecutarlo con: rugby"

# Verificar la instalación ejecutando rugby --version
echo ""
echo "🔍 Verificando la instalación..."
source ~/.zshrc && rugby --version

echo ""
echo "🚀 Ejemplo de uso:"
echo "rugby --version"
echo "rugby cache -e TuPod -v -o fold -v"
