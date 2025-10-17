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

# Default powerful settings (change here if chaho)
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

# function to backup and rewrite a compose file while keeping the same name
rewrite_compose() {
  local file="$1"      # windows10.yml etc
  local ver="$2"       # "10" / "11" / "7"
  local container_name="$3"
  local port_base="$4"
  local data_dir="${DEFAULT_DISK_BASE}/${container_name}"

  mkdir -p "${data_dir}"
  chmod 777 "${data_dir}"

  if [ -f "${file}" ]; then
    cp -v "${file}" "${file}.bak" || true
    echo -e "${YELLOW}Backup created: ${file}.bak${NC}"
  fi

  # Build a docker-compose content that uses env vars and includes GPU/dev mappings if available.
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
      - /dev/net/tun:/dev/net/tun"
EOF

  # Append GPU-specific settings if present
  if [ $HAS_NVIDIA -eq 1 ]; then
    cat >> "${file}" <<'EOF'
    # NVIDIA GPU support (host must have nvidia-container-toolkit)
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
EOF
  elif [ $HAS_DRI -eq 1 ]; then
    # map /dev/dri for iGPU acceleration
    cat >> "${file}" <<'EOF'
    # Intel/AMD iGPU support (/dev/dri mapped)
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

# Which files to update (only if present or user wants to create)
FILES_AND_DETAILS=(
  "windows10.yml|10|windows10|8006"
  "windows11.yml|11|windows11|8011"
  "windows7.yml|7|windows7|8007"
)

echo -e "${CYAN}Processing compose files (backup -> rewrite) ...${NC}"
for entry in "${FILES_AND_DETAILS[@]}"; do
  IFS='|' read -r fname ver cname port <<< "$entry"
  # If file exists, update it. If not exists, create new (user asked not to change names).
  echo -e "${YELLOW}Updating/Creating: ${fname}${NC}"
  rewrite_compose "$fname" "$ver" "$cname" "$port"
  # Bring up (this may recreate container but won't delete volumes)
  echo -e "${CYAN}Running: docker compose -f ${fname} up -d${NC}"
  docker compose -f "${fname}" up -d || echo -e "${YELLOW}docker compose up returned non-zero (check logs)${NC}"
  echo
done

echo -e "${GREEN}All requested compose files processed. Containers may have been restarted/recreated.${NC}"
echo -e "${YELLOW}Note: Data volumes are preserved; no explicit removal was performed.${NC}"
echo

# Provide a simple runtime summary
echo -e "${CYAN}Runtime summary:${NC}"
docker ps --filter "name=windows" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo

# End message and game compatibility table
cat <<'EOF'

========================================
Game compatibility — expected result
(With this upgraded config: RAM=16G, CPUs=8, GPU passthrough if host supports)
Legend: ✅ Likely to run well | ⚠️ May run with issues | ❌ Unlikely / fails
========================================

✅ Likely / Smooth (older/light games)
 - GTA III (1999)                        : ✅
 - GTA Vice City / San Andreas           : ✅
 - Counter-Strike 1.6 / CS Source        : ✅
 - Need for Speed (older titles)         : ✅
 - Minecraft (moderate settings)         : ✅
 - Age of Empires / older RTS            : ✅

⚠️ Possible (may need tweaks — lower settings / driver work)
 - GTA IV                                : ⚠️ (some stuttering, driver issues)
 - Skyrim (original)                      : ⚠️ (medium settings)
 - Euro Truck Simulator 2                : ⚠️ (might need tuning)
 - Rocket League (older builds)          : ⚠️

❌ Unlikely or problematic (anti-cheat / high-end GPU needed / virtualization blocks)
 - GTA V                                 : ❌ (anti-cheat + DirectX + GPU passthrough issues)
 - PUBG / Apex / Fortnite                 : ❌
 - Valorant (Vanguard anti-cheat)         : ❌ (anti-cheat blocks virtualization)
 - Modern AAA (Cyberpunk 2077, RDR2)      : ❌ (very unlikely to be playable)
 - VR titles                              : ❌ (very hardware-specific)

Notes:
 - For ✅ games you still need appropriate GPU drivers in the guest (dockurr/windows image may provide basic drivers; better if you can install official GPU drivers inside the Windows guest).
 - For ⚠️ games, try lowering in-game settings and ensure host GPU drivers + container toolkit (nvidia-container-toolkit) are installed.
 - For ❌ games, virtualization + anti-cheat + GPU passthrough complexity causes failure in most setups. Use bare-metal Windows or a proper VM with exclusive GPU passthrough (QEMU/KVM with vfio) or cloud gaming.

========================================
EOF

echo -e "${GREEN}Done. Agar chaho to main ab specific game ke liye tweak kar dunga (example: GTA V optimizations / try Proxmox QEMU passthrough steps). Batao kaunsa game chahiye sabse pehle?${NC}"
