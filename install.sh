#!/usr/bin/env bash
# Install mount-media-vhdx and its systemd service.
set -Eeuo pipefail

readonly BIN="/usr/local/bin/mount-media-vhdx"
readonly CONFIG_FILE="/etc/media-vhdx.conf"
readonly UNIT_FILE="/etc/systemd/system/media-vhdx.service"
readonly REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Instala o mount-media-vhdx e o serviço systemd media-vhdx.service.

Uso:
  $0              Instala (ou atualiza) o script e o serviço
  $0 --uninstall  Desmonta, desativa e remove o script e o serviço
                  (mantém $CONFIG_FILE)
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  ""|--uninstall) ;;
  *) usage >&2; exit 2 ;;
esac

if (( EUID != 0 )); then
  exec sudo "$REPO_DIR/install.sh" "$@"
fi

if [[ "${1:-}" == "--uninstall" ]]; then
  if systemctl is-active --quiet media-vhdx.service; then
    systemctl stop media-vhdx.service
  fi
  systemctl disable media-vhdx.service 2>/dev/null || true
  rm -f "$UNIT_FILE" "$BIN"
  systemctl daemon-reload
  echo "Removidos: $BIN e $UNIT_FILE (a configuração em $CONFIG_FILE foi mantida)."
  exit 0
fi

for cmd in qemu-nbd partx blkid findmnt flock; do
  command -v "$cmd" >/dev/null || { echo "Erro: '$cmd' não encontrado. Veja os requisitos no README." >&2; exit 1; }
done

install -Dm755 "$REPO_DIR/mount-media-vhdx" "$BIN"
echo "Instalado: $BIN"

if [[ ! -e "$CONFIG_FILE" ]]; then
  install -Dm644 "$REPO_DIR/media-vhdx.conf.example" "$CONFIG_FILE"
  echo "Criado: $CONFIG_FILE (revise antes de montar!)"
fi

# Read the mount points from the config so the unit orders itself after them.
WIN_MNT="/mnt/win11"
MEDIA_MNT="/mnt/media-vhdx"
MEDIA_UID="${SUDO_UID:-1000}"
# shellcheck source=/dev/null
source "$CONFIG_FILE"

cat >"$UNIT_FILE" <<EOF
[Unit]
Description=VHDX de mídia em $MEDIA_MNT
# Stop (unmount) before systemd tears down these mounts at shutdown.
After=local-fs.target $(systemd-escape -p --suffix=mount "$WIN_MNT") $(systemd-escape -p --suffix=mount "$MEDIA_MNT")

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=MEDIA_UID=$MEDIA_UID
ExecStart=$BIN --root
ExecStop=$BIN --root --umount
TimeoutStartSec=90
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
echo "Instalado: $UNIT_FILE"

cat <<EOF

Próximos passos:
  1. Revise $CONFIG_FILE
  2. Teste:            mount-media-vhdx
  3. Desmonte:         mount-media-vhdx --umount
  4. Montar no boot:   sudo systemctl enable media-vhdx
EOF
