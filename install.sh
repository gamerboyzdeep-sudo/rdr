#!/bin/bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}=== Windows Docker Powerful Upgrader (keeps same yml names) ===${NC}"
echo

# Default powerful settings (change here if you want)
DEFAULT_RAM="16G"
DEFAULT_CPUS="8"
DEFAULT_DISK_BASE="/tmp/docker-data"
WINDOWS_USER="Deepak"
WINDOWS_PASS="sankhla"

# Detect GPU support
HAS_NVIDIA=0
HAS_DRI=0
if command -v nvidia-smi >/dev/null 2>&1; then
  HAS_NVIDIA=1
fi
if [ -d /dev/dri ] && [ "$(ls -A /dev/dri 2>/dev/null || true)" != "" ]; then
  HAS_DRI=1
fi

echo -e "${YELLOW}Detected hardware:${NC}"
echo "  NVIDIA present?    : $([ $HAS_NVIDIA -eq 1 ] && echo YES || echo NO)"
echo "  /dev/dri present?  : $([ $HAS_DRI -eq 1 ] && echo YES || echo NO)"
echo

# Create .env or update it
cat > .env <<EOF
WINDOWS_USERNAME=${WINDOWS_USER}
WINDOWS_PASSWORD=${WINDOWS_PASS}
RAM_SIZE=${DEFAULT_RAM}
CPU_CORES=${DEFAULT_CPUS}
EOF
chmod 600 .env
echo -e "${GREEN}.env saved (RAM_SIZE=${DEFAULT_RAM}, CPU_CORES=${DEFAULT_CPUS})${NC}"
echo

# Function to backup and rewrite compose file (keeps same name)
rewrite_compose() {
  local file="$1"
  local ver="$2"
  local container_name="$3"
  local port_base="$4"
  local data_dir="${DEFAULT_DISK_BASE}/${container_name}"

  mkdir -p "${data_dir}"
  chmod 777 "${data_dir}"

  if [ -f "${file}" ]; then
    cp -v "${file}" "${file}.bak" || true
    echo -e "${YELLOW}Backup created: ${file}.bak${NC}"
  fi

  cat > "${file}" <<EOF
version: "3.8"
services:
  windows:
    image: dockurr/windows
    container_name: ${container_name}
    environment:
      VERSION: "${ver}"
      USERNAME: \${WINDOWS_USERNAME}
      PASSWORD: \${WINDOWS_PASSWORD}
      RAM_SIZE: "\${RAM_SIZE}"
      CPU_CORES: "\${CPU_CORES}"
    cap_add:
      - NET_ADMIN
    ports:
      - "${port_base}:8006"
      - "$((port_base + 3389 - 8006)):3389/tcp"
    volumes:
      - ${data_dir}:/mnt/disco1
      - ${container_name}-data:/mnt/windows-data
    devices:
      - /dev/kvm:/dev/kvm
      - /dev/net/tun:/dev/net/tun
EOF

  if [ $HAS_NVIDIA -eq 1 ]; then
    cat >> "${file}" <<'EOF'
    # NVIDIA GPU support
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
EOF
  elif [ $HAS_DRI -eq 1 ]; then
    cat >> "${file}" <<'EOF'
    # Intel/AMD iGPU support
    devices:
      - /dev/dri:/dev/dri
EOF
  fi

  cat >> "${file}" <<EOF

    restart: always

volumes:
  ${container_name}-data:
EOF

  echo -e "${GREEN}Wrote new compose: ${file} (container: ${container_name})${NC}"
  echo
}

# Files to update / create
FILES_AND_DETAILS=(
  "windows10.yml|10|windows10|8006"
  "windows11.yml|11|windows11|8011"
  "windows7.yml|7|windows7|8007"
)

echo -e "${CYAN}Processing compose files (backup -> rewrite)...${NC}"
for entry in "${FILES_AND_DETAILS[@]}"; do
  IFS='|' read -r fname ver cname port <<< "$entry"
  echo -e "${YELLOW}Updating/Creating: ${fname}${NC}"
  rewrite_compose "$fname" "$ver" "$cname" "$port"
  echo -e "${CYAN}Running: docker compose -f ${fname} up -d${NC}"
  docker compose -f "${fname}" up -d || echo -e "${YELLOW}docker compose up returned non-zero (check logs)${NC}"
  echo
done

echo -e "${GREEN}All requested compose files processed. Containers may have been restarted/recreated.${NC}"
echo -e "${YELLOW}Note: Data volumes are preserved; no explicit removal was performed.${NC}"
echo

# Runtime summary
echo -e "${CYAN}Runtime summary:${NC}"
docker ps --filter "name=windows" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo

# Windows Control Menu
while true; do
  echo
  echo "===== Windows Control Menu ====="
  echo "1) Start Windows 10"
  echo "2) Start Windows 11"
  echo "3) Start Windows 7"
  echo "4) Stop Windows 10"
  echo "5) Stop Windows 11"
  echo "6) Stop Windows 7"
  echo "7) Exit"
  read -p "Enter choice [1-7]: " ch

  case $ch in
    1) docker compose -f windows10.yml up -d ;;
    2) docker compose -f windows11.yml up -d ;;
    3) docker compose -f windows7.yml up -d ;;
    4) docker compose -f windows10.yml down ;;
    5) docker compose -f windows11.yml down ;;
    6) docker compose -f windows7.yml down ;;
    7) echo "Exiting menu."; break ;;
    *) echo "Invalid choice." ;;
  esac
done

echo -e "${GREEN}Script complete!${NC}"
