#!/usr/bin/env bash
# Gera a pasta android/ (se não existir) e aplica as configurações do GAZMAP:
# permissões de GPS em segundo plano, nome do app e versões de build.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ]; then
  flutter create --platforms=android --org br.com.gazire --project-name gazmap .
fi

# O template do Flutter cria um teste de exemplo que não se aplica ao GAZMAP.
if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then
  rm test/widget_test.dart
fi

python3 tool/patch_android.py
echo "Android pronto."
