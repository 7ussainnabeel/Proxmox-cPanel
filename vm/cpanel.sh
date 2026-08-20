#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<<$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/api.func)

function header_info {
  clear
  cat <<"EOF"
********************************
*      ____                  _ *
*  ___|  _ \ __ _ _ __   ___| |*
* / __| |_) / _` | '_ \ / _ \ |*
*| (__|  __/ (_| | | | |  __/ |*
* \___|_|   \__,_|_| |_|\___|_|*
********************************
EOF
}
header_info
echo -e "\n Loading..."
GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
NSAPP="cpanel-vm"
var_os="ubuntu"
var_version="24.04"

YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
BGN=$(echo "\033[4;92m")
GN=$(echo "\033[1;92m")
DGN=$(echo "\033[32m")
CL=$(echo "\033[m")

CL=$(echo "\033[m")
BOLD=$(echo "\033[1m")
BFR="\\r\\033[K"
HOLD=" "
TAB="  "

CM="${TAB}✔️${TAB}${CL}"
CROSS="${TAB}✖️${TAB}${CL}"
INFO="${TAB}💡${TAB}${CL}"
OS="${TAB}🖥️${TAB}${CL}"
CONTAINERTYPE="${TAB}📦${TAB}${CL}"
DISKSIZE="${TAB}💾${TAB}${CL}"
CPUCORE="${TAB}🧠${TAB}${CL}"
RAMSIZE="${TAB}🛠️${TAB}${CL}"
CONTAINERID="${TAB}🆔${TAB}${CL}"
HOSTNAME="${TAB}🏠${TAB}${CL}"
BRIDGE="${TAB}🌉${TAB}${CL}"
GATEWAY="${TAB}🌐${TAB}${CL}"
DEFAULT="${TAB}⚙️${TAB}${CL}"
MACADDRESS="${TAB}🔗${TAB}${CL}"
VLANTAG="${TAB}🏷️${TAB}${CL}"
CREATING="${TAB}🚀${TAB}${CL}"
ADVANCED="${TAB}🧩${TAB}${CL}"
CLOUD="${TAB}☁️${TAB}${CL}"

THIN="discard=on,ssd=1,"
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  post_update_to_api "failed" "${exit_code}"
  echo -e "\n$error_message\n"
  cleanup_vmid
}

function get_valid_nextid() {
  local try_id
  try_id=$(pvesh get /cluster/nextid)
  while true; do
    if [ -f "/etc/pve/qemu-server/${try_id}.conf" ] || [ -f "/etc/pve/lxc/${try_id}.conf" ]; then
      try_id=$((try_id + 1))
      continue
    fi
    if lvs --noheadings -o lv_name | grep -qE "(^|[-_])${try_id}($|[-_])"; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

function cleanup_vmid() {
  if [ -n "${VMID:-}" ] && qm status $VMID &>/dev/null; then
    qm stop $VMID &>/dev/null
    qm destroy $VMID &>/dev/null
  fi
}

function cleanup() {
  local exit_code=$?
  if [ -d "${TEMP_DIR:-}" ]; then
    popd >/dev/null || true
    rm -rf $TEMP_DIR
  fi
  if [[ "${POST_TO_API_DONE:-}" == "true" && "${POST_UPDATE_DONE:-}" != "true" ]]; then
    if [[ $exit_code -eq 0 ]]; then
      post_update_to_api "done" "none"
    else
      post_update_to_api "failed" "$exit_code"
    fi
  fi
}

TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

if whiptail --backtitle "Proxmox VE Helper Scripts" --title "cPanel & WHM VM" --yesno "This will create a New cPanel & WHM VM. Proceed?" 10 58; then
  :
else
  header_info && echo -e "${CROSS}${RD}User exited script${CL}\n" && exit
fi

function msg_info() {
  local msg="$1"
  echo -ne "${TAB}${YW}${HOLD}${msg}${HOLD}"
}

function msg_ok() {
  local msg="$1"
  echo -e "${BFR}${CM}${GN}${msg}${CL}"
}

function msg_error() {
  local msg="$1"
  echo -e "${BFR}${CROSS}${RD}${msg}${CL}"
}

function check_root() {
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p $PPID) == "sudo" ]]; then
    clear
    msg_error "Please run this script as root."
    echo -e "\nExiting..."
    sleep 2
    exit
  fi
}

pve_check() {
  local PVE_VER
  PVE_VER="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"

  # Check for Proxmox VE 8.x: allow 8.0–8.9
  if [[ "$PVE_VER" =~ ^8\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 9)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 8.0 – 8.9"
      exit 105
    fi
    return 0
  fi

  # Check for Proxmox VE 9.x: allow 9.0 to 9.2
  if [[ "$PVE_VER" =~ ^9\.([0-9]+) ]]; then
    local MINOR="${BASH_REMATCH[1]}"
    if ((MINOR < 0 || MINOR > 2)); then
      msg_error "This version of Proxmox VE is not supported."
      msg_error "Supported: Proxmox VE version 9.0 – 9.2"
      exit 105
    fi
    return 0
  fi

  msg_error "This version of Proxmox VE is not supported."
  msg_error "Supported versions: Proxmox VE 8.0 – 8.x or 9.0 – 9.2"
  exit 105
}

function arch_check() {
  if [ "$(dpkg --print-architecture)" != "amd64" ]; then
    echo -e "\n ${INFO}${YWB}This script will not work on non-amd64 architectures! \n"
    echo -e "Exiting..."
    sleep 2
    exit
  fi
}

function ssh_check() {
  if command -v pveversion >/dev/null 2>&1; then
    if [ -n "${SSH_CLIENT:+x}" ]; then
      if whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH DETECTED" --yesno "It's suggested to use the Proxmox shell instead of SSH, since SSH can create issues while gathering variables. Would you like to proceed with using SSH?" 10 62; then
        echo "you've been warned"
      else
        clear
        exit
      fi
    fi
  fi
}

function exit-script() {
  clear
  echo -e "\n${CROSS}${RD}User exited script${CL}\n"
  exit
}

function validate_ip_cidr() {
  local ip_cidr="$1"
  if [[ "$ip_cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
    local ip="${ip_cidr%/*}"
    IFS='.' read -ra octets <<<"$ip"
    for octet in "${octets[@]}"; do
      ((octet > 255)) && return 1
    done
    return 0
  fi
  return 1
}

function validate_ip() {
  local ip="$1"
  if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IFS='.' read -ra octets <<<"$ip"
    for octet in "${octets[@]}"; do
      ((octet > 255)) && return 1
    done
    return 0
  fi
  return 1
}

function prompt_cpanel_network() {
  # FQDN Hostname
  while true; do
    if HOSTNAME_FQDN=$(whiptail --backtitle "Proxmox cPanel Installer" --inputbox "Set FQDN Hostname for cPanel (e.g., cpanel.example.com)" 8 58 "${HN}.example.com" --title "FQDN HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [[ "$HOSTNAME_FQDN" == *.* && "$HOSTNAME_FQDN" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        HN=$(echo "$HOSTNAME_FQDN" | cut -d'.' -f1)
        echo -e "${HOSTNAME}${BOLD}${DGN}FQDN Hostname: ${BGN}$HOSTNAME_FQDN${CL}"
        break
      fi
      whiptail --backtitle "Proxmox cPanel Installer" --title "INVALID HOSTNAME" --msgbox "Hostname must be a fully-qualified domain name containing at least one dot (e.g., cpanel.example.com)." 8 58
    else
      exit-script
    fi
  done

  # Static IP
  while true; do
    if IP_ADDRESS_CIDR=$(whiptail --backtitle "Proxmox cPanel Installer" --inputbox "Set Static IPv4 Address with CIDR prefix (e.g., 192.168.1.100/24)" 9 58 "" --title "STATIC IP ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if validate_ip_cidr "$IP_ADDRESS_CIDR"; then
        echo -e "${GATEWAY}${BOLD}${DGN}Static IP: ${BGN}$IP_ADDRESS_CIDR${CL}"
        break
      fi
      whiptail --backtitle "Proxmox cPanel Installer" --title "INVALID IP" --msgbox "Invalid IP format. Please use CIDR format (e.g., 192.168.1.100/24)." 10 50
    else
      exit-script
    fi
  done

  # Gateway IP
  while true; do
    if GATEWAY_IP=$(whiptail --backtitle "Proxmox cPanel Installer" --inputbox "Set Gateway IP Address (e.g., 192.168.1.1)" 8 58 "" --title "GATEWAY IP" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if validate_ip "$GATEWAY_IP"; then
        echo -e "${GATEWAY}${BOLD}${DGN}Gateway IP: ${BGN}$GATEWAY_IP${CL}"
        break
      fi
      whiptail --backtitle "Proxmox cPanel Installer" --title "INVALID GATEWAY" --msgbox "Invalid Gateway format. Please use standard IP format (e.g., 192.168.1.1)." 10 50
    else
      exit-script
    fi
  done

  # DNS Servers
  if DNS_SERVERS=$(whiptail --backtitle "Proxmox cPanel Installer" --inputbox "Set DNS Servers (space-separated)" 8 58 "1.1.1.1 8.8.8.8" --title "DNS SERVERS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    [[ -z "$DNS_SERVERS" ]] && DNS_SERVERS="1.1.1.1 8.8.8.8"
    echo -e "${DEFAULT}${BOLD}${DGN}DNS Servers: ${BGN}$DNS_SERVERS${CL}"
  else
    exit-script
  fi

  # Password (Prompt root password)
  while true; do
    if ROOT_PASSWORD=$(whiptail --backtitle "Proxmox cPanel Installer" --passwordbox "Set Root Password for VM (leave blank for random)" 8 58 --title "ROOT PASSWORD" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$ROOT_PASSWORD" ]; then
        ROOT_PASSWORD=$(openssl rand -base64 12)
        whiptail --backtitle "Proxmox cPanel Installer" --title "PASSWORD GENERATED" --msgbox "Your randomly generated root password is:\n\n  $ROOT_PASSWORD\n\nPlease note this down!" 10 58
      fi
      echo -e "${DEFAULT}${BOLD}${DGN}Root Password: ${BGN}(Configured)${CL}"
      break
    else
      exit-script
    fi
  done
}

function default_settings() {
  VMID=$(get_valid_nextid)
  MACHINE=" -machine q35"
  DISK_SIZE="100G"
  DISK_CACHE=""
  HN="cpanel"
  CPU_TYPE=" -cpu host"
  CORE_COUNT="4"
  RAM_SIZE="8192"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"
  echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}${VMID}${CL}"
  echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}q35${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${DISK_SIZE}${CL}"
  echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
  echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
  echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CORE_COUNT}${CL}"
  echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${RAM_SIZE}${CL}"
  echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}${BRG}${CL}"
  echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}${MAC}${CL}"
  echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}Default${CL}"
  echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}Default${CL}"
  echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
  echo -e "${CREATING}${BOLD}${DGN}Creating a cPanel & WHM VM using the above default settings${CL}"
}

function advanced_settings() {
  METHOD="advanced"
  [ -z "${VMID:-}" ] && VMID=$(get_valid_nextid)
  while true; do
    if VMID=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Virtual Machine ID" 8 58 "$VMID" --title "VIRTUAL MACHINE ID" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VMID" ]; then
        VMID=$(get_valid_nextid)
      fi
      if pct status "$VMID" &>/dev/null || qm status "$VMID" &>/dev/null; then
        echo -e "${CROSS}${RD} ID $VMID is already in use${CL}"
        sleep 2
        continue
      fi
      echo -e "${CONTAINERID}${BOLD}${DGN}Virtual Machine ID: ${BGN}$VMID${CL}"
      break
    else
      exit-script
    fi
  done

  if MACH=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "MACHINE TYPE" --radiolist --cancel-button Exit-Script "Choose Type" 10 58 2 \
    "q35" "Machine q35 (Recommended)" ON \
    "i440fx" "Machine i440fx" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$MACH" = q35 ]; then
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      MACHINE=" -machine q35"
    else
      echo -e "${CONTAINERTYPE}${BOLD}${DGN}Machine Type: ${BGN}$MACH${CL}"
      MACHINE=""
    fi
  else
    exit-script
  fi

  DISK_SIZE="100"
  if DISK_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Disk Size in GiB (e.g., 100, 150)" 8 58 "$DISK_SIZE" --title "DISK SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    DISK_SIZE=$(echo "$DISK_SIZE" | tr -d ' ')
    if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
      DISK_SIZE="${DISK_SIZE}G"
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    elif [[ "$DISK_SIZE" =~ ^[0-9]+G$ ]]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}$DISK_SIZE${CL}"
    else
      echo -e "${DISKSIZE}${BOLD}${RD}Invalid Disk Size. Please use a number (e.g., 100 or 100G).${CL}"
      exit-script
    fi
  else
    exit-script
  fi

  if DISK_CACHE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "DISK CACHE" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "0" "None (Default)" ON \
    "1" "Write Through" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$DISK_CACHE" = "1" ]; then
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}Write Through${CL}"
      DISK_CACHE="cache=writethrough,"
    else
      echo -e "${DISKSIZE}${BOLD}${DGN}Disk Cache: ${BGN}None${CL}"
      DISK_CACHE=""
    fi
  else
    exit-script
  fi

  if VM_NAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Hostname" 8 58 cpanel --title "HOSTNAME" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$VM_NAME" ]; then
      HN="cpanel"
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    else
      HN=$(echo "${VM_NAME,,}" | tr -cs 'a-z0-9-' '-' | sed 's/^-//;s/-$//')
      if [ "$HN" != "${VM_NAME,,}" ]; then
        whiptail --backtitle "Proxmox VE Helper Scripts" --title "HOSTNAME ADJUSTED" --msgbox "Invalid characters detected. Hostname has been adjusted to:\n\n  $HN" 10 58
      fi
      echo -e "${HOSTNAME}${BOLD}${DGN}Hostname: ${BGN}$HN${CL}"
    fi
  else
    exit-script
  fi

  if CPU_TYPE1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CPU MODEL" --radiolist "Choose" --cancel-button Exit-Script 10 58 2 \
    "1" "Host (Recommended)" ON \
    "0" "KVM64" OFF \
    3>&1 1>&2 2>&3); then
    if [ "$CPU_TYPE1" = "1" ]; then
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}Host${CL}"
      CPU_TYPE=" -cpu host"
    else
      echo -e "${OS}${BOLD}${DGN}CPU Model: ${BGN}KVM64${CL}"
      CPU_TYPE=""
    fi
  else
    exit-script
  fi

  while true; do
    if CORE_COUNT=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate CPU Cores" 8 58 4 --title "CORE COUNT" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$CORE_COUNT" ]; then CORE_COUNT="4"; fi
      if [[ "$CORE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}$CORE_COUNT${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "CPU Cores must be a positive integer (e.g., 4)." 8 58
    else
      exit-script
    fi
  done

  while true; do
    if RAM_SIZE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Allocate RAM in MiB" 8 58 8192 --title "RAM" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$RAM_SIZE" ]; then RAM_SIZE="8192"; fi
      if [[ "$RAM_SIZE" =~ ^[1-9][0-9]*$ ]]; then
        echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}$RAM_SIZE${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "RAM Size must be a positive integer in MiB (e.g., 8192)." 8 58
    else
      exit-script
    fi
  done

  if BRG=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Bridge" 8 58 vmbr0 --title "BRIDGE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
    if [ -z "$BRG" ]; then
      BRG="vmbr0"
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    else
      echo -e "${BRIDGE}${BOLD}${DGN}Bridge: ${BGN}$BRG${CL}"
    fi
  else
    exit-script
  fi

  while true; do
    if MAC1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a MAC Address" 8 58 "$GEN_MAC" --title "MAC ADDRESS" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$MAC1" ]; then
        MAC="$GEN_MAC"
        echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC${CL}"
        break
      fi
      if [[ "$MAC1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        MAC="$MAC1"
        echo -e "${MACADDRESS}${BOLD}${DGN}MAC Address: ${BGN}$MAC1${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "Invalid MAC address format. Use XX:XX:XX:XX:XX:XX (e.g., AA:BB:CC:DD:EE:FF)." 8 58
    else
      exit-script
    fi
  done

  while true; do
    if VLAN1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set a Vlan (leave blank for default)" 8 58 --title "VLAN" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$VLAN1" ]; then
        VLAN1="Default"
        VLAN=""
        echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
        break
      fi
      if [[ "$VLAN1" =~ ^[0-9]+$ ]] && [ "$VLAN1" -ge 1 ] && [ "$VLAN1" -le 4094 ]; then
        VLAN=",tag=$VLAN1"
        echo -e "${VLANTAG}${BOLD}${DGN}VLAN: ${BGN}$VLAN1${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "VLAN must be a number between 1 and 4094, or leave blank for default." 8 58
    else
      exit-script
    fi
  done

  while true; do
    if MTU1=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set Interface MTU Size (leave blank for default)" 8 58 --title "MTU SIZE" --cancel-button Exit-Script 3>&1 1>&2 2>&3); then
      if [ -z "$MTU1" ]; then
        MTU1="Default"
        MTU=""
        echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
        break
      fi
      if [[ "$MTU1" =~ ^[0-9]+$ ]] && [ "$MTU1" -ge 576 ] && [ "$MTU1" -le 65520 ]; then
        MTU=",mtu=$MTU1"
        echo -e "${DEFAULT}${BOLD}${DGN}Interface MTU Size: ${BGN}$MTU1${CL}"
        break
      fi
      whiptail --backtitle "Proxmox VE Helper Scripts" --title "INVALID INPUT" --msgbox "MTU Size must be a number between 576 and 65520, or leave blank for default." 8 58
    else
      exit-script
    fi
  done

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "START VIRTUAL MACHINE" --yesno "Start VM when completed?" 10 58); then
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}yes${CL}"
    START_VM="yes"
  else
    echo -e "${GATEWAY}${BOLD}${DGN}Start VM when completed: ${BGN}no${CL}"
    START_VM="no"
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "ADVANCED SETTINGS COMPLETE" --yesno "Ready to create a cPanel & WHM VM?" --no-button Do-Over 10 58); then
    echo -e "${CREATING}${BOLD}${DGN}Creating a cPanel & WHM VM using the above advanced settings${CL}"
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

function start_script() {
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno "Use Default Settings?" --no-button Advanced 10 58); then
    header_info
    echo -e "${DEFAULT}${BOLD}${BL}Using Default Settings${CL}"
    default_settings
  else
    header_info
    echo -e "${ADVANCED}${BOLD}${RD}Using Advanced Settings${CL}"
    advanced_settings
  fi
}

check_root
arch_check
pve_check
ssh_check
start_script
prompt_cpanel_network
post_to_api_vm

msg_info "Validating Storage"
while read -r line; do
  TAG=$(echo "$line" | awk '{print $1}')
  TYPE=$(echo "$line" | awk '{printf "%-10s", $2}')
  FREE=$(echo "$line" | numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | awk '{printf( "%9sB", $6)}')
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=("$TAG" "$ITEM" "OFF")
done < <(pvesm status -content images | awk 'NR>1')
VALID=$(pvesm status -content images | awk 'NR>1')
if [ -z "$VALID" ]; then
  msg_error "Unable to detect a valid storage location."
  exit
elif [ $((${#STORAGE_MENU[@]} / 3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use for ${HN}?\nTo make a selection, use the Spacebar.\n" \
      16 $(($MSG_MAX_LENGTH + 23)) 6 \
      "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3)
  done
fi
msg_ok "Using ${CL}${BL}$STORAGE${CL} ${GN}for Storage Location."
msg_ok "Virtual Machine ID is ${CL}${BL}$VMID${CL}."

# Prerequisites installation (libguestfs-tools for image customizations)
if ! command -v virt-customize &>/dev/null; then
  msg_info "Installing libguestfs-tools on Proxmox host"
  apt-get -qq update >/dev/null
  apt-get -qq install libguestfs-tools -y >/dev/null
  msg_ok "Installed libguestfs-tools"
fi

msg_info "Retrieving the URL for the Ubuntu 24.04 LTS Cloud Image"
URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
CACHE_DIR="/var/lib/vz/template/cache"
CACHE_FILE="$CACHE_DIR/noble-server-cloudimg-amd64.img"
mkdir -p "$CACHE_DIR"
sleep 2
msg_ok "${CL}${BL}${URL}${CL}"

if [[ ! -s "$CACHE_FILE" ]]; then
  msg_info "Downloading Ubuntu 24.04 LTS Cloud Image"
  curl -f#SL -o "$CACHE_FILE" "$URL"
  echo -en "\e[1A\e[0K"
  msg_ok "Downloaded ${CL}${BL}$(basename "$CACHE_FILE")${CL}"
else
  msg_ok "Using cached image ${CL}${BL}$(basename "$CACHE_FILE")${CL}"
fi

STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir | cifs)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="--format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="--format raw"
  THIN=""
  ;;
*)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="--format raw"
  ;;
esac

msg_info "Preparing Ubuntu image with cPanel installer"
WORK_FILE="${TEMP_DIR}/ubuntu.qcow2"
cp "$CACHE_FILE" "$WORK_FILE"

export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1

# Install guest packages inside VM image
virt-customize -q -a "$WORK_FILE" --run-command "apt-get update" --install qemu-guest-agent,curl,ca-certificates,perl,perl-base,wget >/dev/null 2>&1

# Write first-boot helper script inside image
virt-customize -q -a "$WORK_FILE" --write "/root/install-cpanel.sh:
#!/usr/bin/env bash
exec > /var/log/cpanel-install.log 2>&1
echo \"[\$(date)] Starting cPanel installation...\"

# Wait for internet connectivity
for i in {1..30}; do
  ping -c 1 8.8.8.8 >/dev/null 2>&1 && break
  sleep 5
done

# Disable firewall (UFW) as required by cPanel on Ubuntu
iptables-save > /root/firewall.rules
systemctl stop ufw.service 2>/dev/null || true
systemctl disable ufw.service 2>/dev/null || true

# Run official cPanel installer
cd /home
curl -o latest -L https://securedownloads.cpanel.net/latest
sh latest

touch /root/.cpanel-installed
echo \"[\$(date)] cPanel installation finished.\"
" >/dev/null 2>&1

virt-customize -q -a "$WORK_FILE" --chmod "0700" "/root/install-cpanel.sh" >/dev/null 2>&1

# Create systemd service inside image to trigger cPanel setup on boot
virt-customize -q -a "$WORK_FILE" --write "/etc/systemd/system/install-cpanel.service:
[Unit]
Description=Install cPanel on First Boot
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/root/.cpanel-installed

[Service]
Type=oneshot
ExecStart=/root/install-cpanel.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
" >/dev/null 2>&1

virt-customize -q -a "$WORK_FILE" --run-command "systemctl enable install-cpanel.service" >/dev/null 2>&1

# Finalize image configurations
virt-customize -q -a "$WORK_FILE" --hostname "${HOSTNAME_FQDN}" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "truncate -s 0 /etc/machine-id" >/dev/null 2>&1 || true
virt-customize -q -a "$WORK_FILE" --run-command "rm -f /var/lib/dbus/machine-id" >/dev/null 2>&1 || true

# Allow SSH root / password auth (extremely thorough config for Ubuntu 24.04 compatibility)
virt-customize -q -a "$WORK_FILE" \
  --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" \
  --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" \
  --run-command "sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config.d/* 2>/dev/null || true" \
  --run-command "echo 'ssh_pwauth: true' >> /etc/cloud/cloud.cfg 2>/dev/null || true" >/dev/null 2>&1 || true

msg_ok "Prepared Ubuntu image with cPanel installer"

msg_info "Creating a cPanel & WHM VM shell"
qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null
msg_ok "Created VM shell"

msg_info "Importing customized disk into storage ($STORAGE)"
if qm disk import --help >/dev/null 2>&1; then
  IMPORT_CMD=(qm disk import)
else
  IMPORT_CMD=(qm importdisk)
fi

IMPORT_OUT="$("${IMPORT_CMD[@]}" "$VMID" "${WORK_FILE}" "$STORAGE" ${DISK_IMPORT:-} 2>&1 || true)"
DISK_REF_IMPORTED="$(printf '%s\n' "$IMPORT_OUT" | sed -n "s/.*successfully imported disk '\([^']\+\)'.*/\1/p" | tr -d "\r\"'")"
[[ -z "$DISK_REF_IMPORTED" ]] && DISK_REF_IMPORTED="$(pvesm list "$STORAGE" | awk -v id="$VMID" '$5 ~ ("vm-"id"-disk-") {print $1":"$5}' | sort | tail -n1)"
[[ -z "$DISK_REF_IMPORTED" ]] && {
  msg_error "Unable to determine imported disk reference."
  echo "$IMPORT_OUT"
  exit 226
}
msg_ok "Imported disk (${CL}${BL}${DISK_REF_IMPORTED}${CL})"

# Cleanup temporary files
rm -f "$WORK_FILE"

msg_info "Configuring Native Cloud-Init & EFI disk"
qm set $VMID \
  -efidisk0 ${STORAGE}:0,efitype=4m \
  -scsi0 ${DISK_REF_IMPORTED},${DISK_CACHE}${THIN%,} \
  -ide2 ${STORAGE}:cloudinit \
  -boot order=scsi0 \
  -ipconfig0 "ip=${IP_ADDRESS_CIDR},gw=${GATEWAY_IP}" \
  -nameserver "${DNS_SERVERS}" \
  -searchdomain "local" \
  -ciuser "root" \
  -cipassword "${ROOT_PASSWORD}" \
  -ciupgrade 0 \
  -serial0 socket >/dev/null

DESCRIPTION=$(
  cat <<EOF
<div align='center'>
  <a href='https://community-scripts.org' target='_blank' rel='noopener noreferrer'>
    <img src='https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/images/logo-81x112.png' alt='Logo' style='width:81px;height:112px;'/>
  </a>

  <h2 style='font-size: 24px; margin: 20px 0;'>cPanel & WHM VM</h2>

  <p style='margin: 16px 0;'>
    <a href='https://ko-fi.com/community_scripts' target='_blank' rel='noopener noreferrer'>
      <img src='https://img.shields.io/badge/&#x2615;-Buy us a coffee-blue' alt='spend Coffee' />
    </a>
  </p>
  
  <span style='margin: 0 10px;'>
    <i class="fa fa-github fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>GitHub</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-comments fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE/discussions' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Discussions</a>
  </span>
  <span style='margin: 0 10px;'>
    <i class="fa fa-exclamation-circle fa-fw" style="color: #f5f5f5;"></i>
    <a href='https://github.com/community-scripts/ProxmoxVE/issues' target='_blank' rel='noopener noreferrer' style='text-decoration: none; color: #00617f;'>Issues</a>
  </span>
</div>
EOF
)
qm set $VMID -description "$DESCRIPTION" >/dev/null
msg_ok "Configured Cloud-Init & VM settings"

if [ -n "$DISK_SIZE" ]; then
  msg_info "Resizing disk to $DISK_SIZE"
  qm resize $VMID scsi0 ${DISK_SIZE} >/dev/null
  msg_ok "Resized disk to $DISK_SIZE"
fi

msg_ok "Created a cPanel & WHM VM ${CL}${BL}(${HN})"

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting cPanel & WHM VM"
  qm start $VMID
  msg_ok "Started cPanel & WHM VM"
fi

post_update_to_api "done" "none"

echo -e "\n${INFO}${BOLD}${GN}cPanel & WHM VM Configuration Summary:${CL}"
echo -e "${TAB}${DGN}VM ID: ${BGN}${VMID}${CL}"
echo -e "${TAB}${DGN}Hostname: ${BGN}${HOSTNAME_FQDN}${CL}"
echo -e "${TAB}${DGN}Static IP: ${BGN}${IP_ADDRESS_CIDR%/*}${CL}"
echo -e "${TAB}${DGN}Root User: ${BGN}root${CL}"
echo -e "${TAB}${DGN}Root Password: ${BGN}${ROOT_PASSWORD}${CL}"
echo -e "${TAB}${DGN}WHM Portal: ${BGN}https://${IP_ADDRESS_CIDR%/*}:2087${CL}"
echo -e "${TAB}${DGN}cPanel Portal: ${BGN}https://${IP_ADDRESS_CIDR%/*}:2083${CL}"
echo -e "\n${TAB}${YW}⚠️  cPanel installation runs in the background on first boot.${CL}"
echo -e "${TAB}${YW}⚠️  It may take 15-40 minutes to complete.${CL}"
echo -e "${TAB}${YW}⚠️  Track progress via Console: ${BL}tail -f /var/log/cpanel-install.log${CL}"

msg_ok "Completed successfully!\n"