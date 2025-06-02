#!/bin/bash
# Script de instalação para configurar o serviço de limpeza de kernels

# Nome do script
SCRIPT_NAME="fedora-kernel-cleanup.sh"
# Caminho onde o script será instalado
SCRIPT_PATH="/usr/local/bin/$SCRIPT_NAME"
# Nome do serviço systemd
SERVICE_NAME="fedora-kernel-cleanup.service"
# Caminho para o arquivo de serviço
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
# Caminho para o arquivo de timer (opcional)
TIMER_PATH="/etc/systemd/system/fedora-kernel-cleanup.timer"

# Verifica permissões de root
if [ "$(id -u)" -ne 0 ]; then
  echo "Este script precisa ser executado como root ou com sudo."
  exit 1
fi

# Cria o script de limpeza de kernels no caminho de destino
cat >"$SCRIPT_PATH" <<'EOF'
#!/bin/bash
# Script para manter apenas os N kernels mais recentes no Fedora

# Configurações padrão
KEEP_KERNELS=2
LOG_FILE="/var/log/kernel-cleanup.log"

# Função para registrar mensagens
log_message() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
}

# Iniciar o log
log_message "Iniciando limpeza de kernels. Mantendo os $KEEP_KERNELS mais recentes."

# Obter a versão atual do kernel em execução
CURRENT_KERNEL=$(uname -r)
log_message "Kernel atual: $CURRENT_KERNEL"

# Obter a lista de todos os kernels instalados (ordenados por versão)
ALL_KERNELS=$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V)
if [ $? -ne 0 ]; then
    log_message "Erro ao obter a lista de kernels instalados. Verifique se você está usando Fedora."
    exit 1
fi

# Contar quantos kernels estão instalados
KERNEL_COUNT=$(echo "$ALL_KERNELS" | wc -l)
log_message "Total de kernels instalados: $KERNEL_COUNT"

# Se houver N ou menos kernels, não há nada para fazer
if [ "$KERNEL_COUNT" -le "$KEEP_KERNELS" ]; then
    log_message "Apenas $KERNEL_COUNT kernel(s) instalado(s). Nada a fazer."
    exit 0
fi

# Identificar os kernels a serem mantidos (os N mais recentes)
KERNELS_TO_KEEP=$(echo "$ALL_KERNELS" | tail -n "$KEEP_KERNELS")
log_message "Kernels que serão mantidos:"
echo "$KERNELS_TO_KEEP" | while read -r kernel; do
    log_message "  - $kernel"
done

# Identificar kernels para remover (todos exceto os N mais recentes)
KERNELS_TO_REMOVE=$(echo "$ALL_KERNELS" | head -n $((KERNEL_COUNT - KEEP_KERNELS)))
log_message "Kernels que serão removidos:"
echo "$KERNELS_TO_REMOVE" | while read -r kernel; do
    log_message "  - $kernel"
done

# Verificar se o kernel atual está na lista de remoção
CURRENT_KERNEL_BASE=$(echo "$CURRENT_KERNEL" | sed 's/\(.*\)\.fc[0-9]*/\1/')
KERNEL_IN_REMOVE=false

for kernel in $KERNELS_TO_REMOVE; do
    if [[ "$kernel" == "$CURRENT_KERNEL_BASE" || "$CURRENT_KERNEL" == *"$kernel"* ]]; then
        log_message "AVISO: O kernel atual ($CURRENT_KERNEL) está marcado para remoção. Abortando."
        exit 1
    fi
done

# Remover os kernels antigos
for kernel in $KERNELS_TO_REMOVE; do
    log_message "Removendo kernel: $kernel"
    dnf remove -y kernel-$kernel
    if [ $? -ne 0 ]; then
        log_message "Aviso: Erro ao remover kernel $kernel. Continuando..."
    fi
done

# Limpar pacotes não utilizados
log_message "Executando limpeza de pacotes não utilizados..."
dnf autoremove -y

# Verificar se o grub precisa ser atualizado
if command -v grub2-mkconfig >/dev/null 2>&1; then
    log_message "Atualizando configuração do GRUB..."
    grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
fi

log_message "Operação concluída. Kernels mantidos:"
echo "$KERNELS_TO_KEEP" | while read -r kernel; do
    log_message "  - $kernel"
done
EOF

# Torna o script executável
chmod +x "$SCRIPT_PATH"

# Cria o arquivo de serviço systemd
cat >"$SERVICE_PATH" <<EOF
[Unit]
Description=Fedora Kernel Cleanup Service
After=network.target dnf-makecache.service
Wants=dnf-makecache.service

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Cria um arquivo de timer para execução após o boot (adiciona um atraso para garantir que o sistema esteja completamente inicializado)
cat >"$TIMER_PATH" <<EOF
[Unit]
Description=Run Fedora Kernel Cleanup after boot

[Timer]
OnBootSec=5min
Unit=$SERVICE_NAME

[Install]
WantedBy=timers.target
EOF

# Recarrega as unidades do systemd
systemctl daemon-reload

# Habilita e inicia o timer
systemctl enable fedora-kernel-cleanup.timer
systemctl start fedora-kernel-cleanup.timer

echo "============================================================"
echo "Configuração concluída!"
echo "O serviço de limpeza de kernels será executado 5 minutos após o boot."
echo "Log será armazenado em /var/log/kernel-cleanup.log"
echo "Para verificar o status do serviço: systemctl status $SERVICE_NAME"
echo "Para verificar o status do timer: systemctl status fedora-kernel-cleanup.timer"
echo "Para executar manualmente: systemctl start $SERVICE_NAME"
echo "============================================================"
