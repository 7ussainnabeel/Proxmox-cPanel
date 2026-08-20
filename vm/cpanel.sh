#!/usr/bin/env bash

# ============================================================
# Proxmox cPanel & WHM VM Installer
# AlmaLinux 9 + KVM
# ============================================================

set -Eeuo pipefail

SCRIPT_NAME="Proxmox cPanel VM Installer"
VERSION="1.0.0"

# ------------------------------------------------------------
# Defaults
# ------------------------------------------------------------

DEFAULT_VM_ID="130"
DEFAULT_VM_NAME="cpanel"
DEFAULT_CORES="4"
DEFAULT_MEMORY="8192"
DEFAULT_DISK="100"
DEFAULT_STORAGE="local-lvm"
DEFAULT_BRIDGE="vmbr0"

ALMA_IMAGE_URL="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------

msg() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

die() {
    error "$*"
    exit 1
}

header() {
    clear 2>/dev/null || true

    echo
    echo "============================================================"
    echo "        $SCRIPT_NAME"
    echo "                     Version $VERSION"
    echo "============================================================"
    echo
}

cleanup() {
    rm -f /tmp/cpanel-cloud-init.yml
    rm -f /tmp/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2
}

trap cleanup EXIT

# ------------------------------------------------------------
# Root / Proxmox checks
# ------------------------------------------------------------

check_environment() {

    [[ $EUID -eq 0 ]] || die "Run this script as root."

    command -v qm >/dev/null 2>&1 || \
        die "This script must be executed on a Proxmox VE host."

    command -v pvesm >/dev/null 2>&1 || \
        die "pvesm was not found."

    command -v wget >/dev/null 2>&1 || \
        die "wget is required."

    command -v qm >/dev/null 2>&1 || \
        die "qm command not found."
}

# ------------------------------------------------------------
# Input
# ------------------------------------------------------------

ask_configuration() {

    echo "============================================================"
    echo "cPanel VM Configuration"
    echo "============================================================"
    echo

    read -rp "VM ID [$DEFAULT_VM_ID]: " VM_ID
    VM_ID="${VM_ID:-$DEFAULT_VM_ID}"

    read -rp "VM Name [$DEFAULT_VM_NAME]: " VM_NAME
    VM_NAME="${VM_NAME:-$DEFAULT_VM_NAME}"

    read -rp "CPU cores [$DEFAULT_CORES]: " CORES
    CORES="${CORES:-$DEFAULT_CORES}"

    read -rp "RAM MB [$DEFAULT_MEMORY]: " MEMORY
    MEMORY="${MEMORY:-$DEFAULT_MEMORY}"

    read -rp "Disk GB [$DEFAULT_DISK]: " DISK
    DISK="${DISK:-$DEFAULT_DISK}"

    read -rp "Proxmox storage [$DEFAULT_STORAGE]: " STORAGE
    STORAGE="${STORAGE:-$DEFAULT_STORAGE}"

    read -rp "Network bridge [$DEFAULT_BRIDGE]: " BRIDGE
    BRIDGE="${BRIDGE:-$DEFAULT_BRIDGE}"

    echo
    echo "------------------------------------------------------------"
    echo "cPanel Network Configuration"
    echo "------------------------------------------------------------"
    echo

    read -rp "Static IPv4 address: " IP_ADDRESS
    [[ -n "$IP_ADDRESS" ]] || die "IPv4 address is required."

    read -rp "CIDR prefix (example 24): " IP_PREFIX
    [[ -n "$IP_PREFIX" ]] || die "CIDR prefix is required."

    read -rp "Gateway: " GATEWAY
    [[ -n "$GATEWAY" ]] || die "Gateway is required."

    read -rp "DNS server 1 [1.1.1.1]: " DNS1
    DNS1="${DNS1:-1.1.1.1}"

    read -rp "DNS server 2 [8.8.8.8]: " DNS2
    DNS2="${DNS2:-8.8.8.8}"

    read -rp "FQDN hostname (example cpanel.example.com): " HOSTNAME_FQDN
    [[ -n "$HOSTNAME_FQDN" ]] || die "FQDN hostname is required."

    echo
    echo "============================================================"
    echo "Configuration Summary"
    echo "============================================================"
    echo
    echo "VM ID       : $VM_ID"
    echo "VM Name     : $VM_NAME"
    echo "CPU         : $CORES cores"
    echo "RAM         : $MEMORY MB"
    echo "Disk        : $DISK GB"
    echo "Storage     : $STORAGE"
    echo "Bridge      : $BRIDGE"
    echo "IPv4        : $IP_ADDRESS/$IP_PREFIX"
    echo "Gateway     : $GATEWAY"
    echo "DNS         : $DNS1, $DNS2"
    echo "Hostname    : $HOSTNAME_FQDN"
    echo

    read -rp "Continue? [y/N]: " CONFIRM

    [[ "$CONFIRM" =~ ^[Yy]$ ]] || {
        echo "Cancelled."
        exit 0
    }
}

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

validate_configuration() {

    if qm status "$VM_ID" >/dev/null 2>&1; then
        die "VM ID $VM_ID already exists."
    fi

    pvesm status --storage "$STORAGE" >/dev/null 2>&1 || \
        die "Storage '$STORAGE' does not exist."

    ip -br link show "$BRIDGE" >/dev/null 2>&1 || \
        warn "Could not verify bridge $BRIDGE. Continuing."

    if ! [[ "$IP_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        die "Invalid IPv4 address: $IP_ADDRESS"
    fi

    if ! [[ "$IP_PREFIX" =~ ^[0-9]{1,2}$ ]]; then
        die "Invalid CIDR prefix."
    fi

    if ! [[ "$HOSTNAME_FQDN" == *.* ]]; then
        die "Hostname must be a fully-qualified domain name."
    fi
}

# ------------------------------------------------------------
# Download AlmaLinux
# ------------------------------------------------------------

download_almalinux() {

    msg "Downloading official AlmaLinux 9 cloud image..."

    wget \
        --show-progress \
        -O /tmp/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2 \
        "$ALMA_IMAGE_URL" || \
        die "Failed to download AlmaLinux."

    [[ -s /tmp/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2 ]] || \
        die "Downloaded AlmaLinux image is empty."

    msg "AlmaLinux image downloaded."
}

# ------------------------------------------------------------
# Create cloud-init configuration
# ------------------------------------------------------------

create_cloud_init() {

    msg "Creating cloud-init configuration..."

    cat > /tmp/cpanel-cloud-init.yml <<EOF
#cloud-config

hostname: ${HOSTNAME_FQDN}
fqdn: ${HOSTNAME_FQDN}

manage_etc_hosts: true

users:
  - name: root
    lock_passwd: false

ssh_pwauth: true

write_files:

  - path: /root/install-cpanel.sh
    permissions: '0700'
    owner: root:root
    content: |
      #!/usr/bin/env bash

      set -Eeuo pipefail

      echo "============================================================"
      echo "Preparing AlmaLinux for cPanel"
      echo "============================================================"

      hostnamectl set-hostname "${HOSTNAME_FQDN}"

      # Disable SELinux as required by cPanel
      if [ -f /etc/selinux/config ]; then
          sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
      fi

      # Disable firewalld during cPanel installation
      systemctl disable --now firewalld 2>/dev/null || true

      # Ensure networking and DNS are ready
      dnf clean all || true
      dnf -y update || true
      dnf -y install perl curl wget || true

      echo
      echo "============================================================"
      echo "Network"
      echo "============================================================"
      ip addr
      echo
      ip route
      echo
      cat /etc/resolv.conf

      echo
      echo "============================================================"
      echo "Hostname"
      echo "============================================================"
      hostname -f

      echo
      echo "============================================================"
      echo "Starting cPanel installation"
      echo "============================================================"

      cd /home

      curl -o latest -L https://securedownloads.cpanel.net/latest

      sh latest

runcmd:

  - [ bash, /root/install-cpanel.sh ]

final_message: |
  cPanel preparation complete.
  The cPanel installer may continue running in the background.
EOF
}

# ------------------------------------------------------------
# Create VM
# ------------------------------------------------------------

create_vm() {

    msg "Creating Proxmox VM $VM_ID..."

    qm create "$VM_ID" \
        --name "$VM_NAME" \
        --memory "$MEMORY" \
        --cores "$CORES" \
        --cpu host \
        --ostype l26 \
        --machine q35 \
        --scsihw virtio-scsi-single \
        --net0 "virtio,bridge=$BRIDGE" \
        --agent 1 \
        --onboot 1 \
        --startup order=3 \
        --balloon 0 \
        || die "Failed to create VM."

    msg "VM created."
}

# ------------------------------------------------------------
# Import AlmaLinux disk
# ------------------------------------------------------------

configure_disk() {

    msg "Importing AlmaLinux disk..."

    qm importdisk \
        "$VM_ID" \
        /tmp/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2 \
        "$STORAGE" \
        --format qcow2 \
        || die "Failed to import AlmaLinux disk."

    msg "Attaching disk..."

    qm set "$VM_ID" \
        --scsi0 "$STORAGE:vm-${VM_ID}-disk-0" \
        || die "Failed to attach disk."

    msg "Resizing disk to ${DISK}G..."

    qm resize "$VM_ID" scsi0 "${DISK}G" \
        || die "Failed to resize disk."
}

# ------------------------------------------------------------
# Cloud-init
# ------------------------------------------------------------

configure_cloud_init() {

    msg "Configuring cloud-init..."

    qm set "$VM_ID" \
        --ide2 "$STORAGE:cloudinit" \
        --boot order=scsi0 \
        || die "Failed to configure cloud-init."

    # Static IP
    qm set "$VM_ID" \
        --ipconfig0 "ip=${IP_ADDRESS}/${IP_PREFIX},gw=${GATEWAY}" \
        || die "Failed to configure IP."

    qm set "$VM_ID" \
        --nameserver "${DNS1} ${DNS2}" \
        || die "Failed to configure DNS."

    qm set "$VM_ID" \
        --ciupgrade 0 \
        || true

    msg "Cloud-init configured."
}

# ------------------------------------------------------------
# Start VM
# ------------------------------------------------------------

start_vm() {

    msg "Starting VM..."

    qm start "$VM_ID" || die "Failed to start VM."

    echo
    echo "============================================================"
    echo "VM STARTED"
    echo "============================================================"
    echo
    echo "VM ID       : $VM_ID"
    echo "VM Name     : $VM_NAME"
    echo "Hostname    : $HOSTNAME_FQDN"
    echo "IPv4        : $IP_ADDRESS"
    echo
}

# ------------------------------------------------------------
# Wait for VM
# ------------------------------------------------------------

wait_for_vm() {

    msg "Waiting for VM network..."

    for i in {1..60}; do

        if ping -c 1 -W 1 "$IP_ADDRESS" >/dev/null 2>&1; then
            msg "VM is responding to ping."
            return 0
        fi

        sleep 5
    done

    warn "VM did not respond to ping yet."
    warn "This does not necessarily mean installation failed."
}

# ------------------------------------------------------------
# Final information
# ------------------------------------------------------------

show_information() {

    echo
    echo "============================================================"
    echo "        cPanel VM DEPLOYMENT STARTED"
    echo "============================================================"
    echo
    echo "VM ID       : $VM_ID"
    echo "VM Name     : $VM_NAME"
    echo "Hostname    : $HOSTNAME_FQDN"
    echo "IPv4        : $IP_ADDRESS"
    echo
    echo "WHM:"
    echo "https://${IP_ADDRESS}:2087"
    echo
    echo "cPanel:"
    echo "https://${IP_ADDRESS}:2083"
    echo
    echo "Installation logs inside the VM:"
    echo "/var/log/cloud-init-output.log"
    echo
    echo "cPanel installation log:"
    echo "/var/log/cpanel-install.log"
    echo
    echo "IMPORTANT:"
    echo "cPanel installation can take a considerable amount of time."
    echo "Do not reboot or destroy the VM while installation is running."
    echo
    echo "============================================================"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

header

check_environment
ask_configuration
validate_configuration
download_almalinux
create_cloud_init
create_vm
configure_disk
configure_cloud_init
start_vm
wait_for_vm
show_information

exit 0