#!/bin/bash

# Script para instalar una versión pre-compilada de Rugby
# Asume que el binario 'rugby' ya está en el directorio actual

# Verificar que el binario existe en el directorio actual
if [ ! -f "./rugby" ]; then
  echo "❌ Error: No se encontró el binario 'rugby' en el directorio actual."
  echo "   Asegúrate de que el archivo 'rugby' esté en la misma carpeta que este script."
  exit 1
fi

# Verificar que el binario es ejecutable y funcional
if [ ! -x "./rugby" ]; then
  echo "🔧 Haciendo el binario ejecutable..."
  chmod +x "./rugby"
fi

# Verificar que el binario funciona
echo "🔍 Verificando que el binario funciona..."
if ! ./rugby --version >/dev/null 2>&1; then
  echo "❌ Error: El binario 'rugby' no parece funcionar correctamente."
  echo "   Verifica que sea compatible con tu sistema ($(uname -m))."
  exit 1
fi

# Directorio de instalación
INSTALL_DIR="$HOME/.rugby/clt"
mkdir -p "$INSTALL_DIR"

# Eliminar versión anterior si existe
if [ -f "$INSTALL_DIR/rugby" ]; then
  echo "🗑️  Eliminando versión anterior de Rugby..."
  rm "$INSTALL_DIR/rugby"
fi

# Copiar el binario
echo "📦 Instalando Rugby en $INSTALL_DIR..."
cp ./rugby "$INSTALL_DIR/rugby"
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

echo "✅ Rugby pre-compilado instalado como 'rugby'"
echo "📋 Puedes ejecutarlo con: rugby"

# Verificar la instalación ejecutando rugby --version
echo ""
echo "🔍 Verificando la instalación..."
# Usar el PATH actualizado para verificar
export PATH="$INSTALL_DIR:$PATH"
rugby --version

echo ""
echo "🚀 Ejemplo de uso:"
echo "rugby --version"
echo "rugby build -v -o fold --except NavigationMocks --except PayMocks --except RappiPaymentMethods"
echo "rugby use -v -o fold --except NavigationMocks --except PayMocks --except RappiPaymentMethods

echo ""
echo "📝 Notas:"
echo "- Si ya tenías Rugby instalado, esta versión tomará precedencia"
echo "- Para usar la versión original, reinstálala o modifica tu PATH"
echo "- Esta instalación es local al usuario actual"
