#!/bin/bash
# Prepara AWS CloudShell para desplegar el proyecto (correr UNA vez por sesión
# de CloudShell; es rápido si ya estaba instalado).
#   - Instala Terraform en ~/bin (persiste entre sesiones de CloudShell).
#   - Pone los plugins de Terraform en /tmp: el AWS provider pesa ~700 MB y el
#     $HOME de CloudShell solo tiene 1 GB. El estado (terraform.tfstate) SÍ queda
#     en infra/, dentro del $HOME, así que no se pierde.
# Uso:  source scripts/preparar_cloudshell.sh
VERSION_TF="1.9.8"
mkdir -p "$HOME/bin"
if ! "$HOME/bin/terraform" version 2>/dev/null | grep -q "$VERSION_TF"; then
  curl -sSLo /tmp/terraform.zip "https://releases.hashicorp.com/terraform/${VERSION_TF}/terraform_${VERSION_TF}_linux_amd64.zip"
  unzip -o -q /tmp/terraform.zip -d "$HOME/bin" && rm /tmp/terraform.zip
fi
grep -q 'TF_DATA_DIR' "$HOME/.bashrc" || cat >> "$HOME/.bashrc" <<'RC'
export PATH="$HOME/bin:$PATH"
export TF_DATA_DIR=/tmp/tfdata-proyecto2
RC
export PATH="$HOME/bin:$PATH"
export TF_DATA_DIR=/tmp/tfdata-proyecto2
terraform version | head -1
aws sts get-caller-identity --query Account --output text | sed 's/^/Cuenta AWS: /'
