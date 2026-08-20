# Proxmox cPanel & WHM VM Installer

An interactive, automated bash installer that deploys a fully configured AlmaLinux 9 Virtual Machine on Proxmox VE, automatically installing **cPanel & WHM**.

The script is styled and structured to look and act exactly like the popular **Proxmox VE Helper-Scripts** (community-scripts).

---

## Features

- 🖥️ **Interactive Whiptail GUI:** Uses standardized Proxmox blue/grey dialogue screens for all resource allocations and configurations.
- ⚙️ **Default & Advanced Presets:**
  - **Default:** Deploys a VM with 4 cores, 8GB RAM, and 100GB Disk with Q35 machine types and Host CPU profiles.
  - **Advanced:** Lets you customize VM ID, CPU cores, RAM, Disk Cache, Bridge interface, MAC address, VLAN tag, and MTU.
- 💿 **AlmaLinux 9 & Image Caching:** Automatically downloads the official AlmaLinux 9 Generic Cloud image and caches it in `/var/lib/vz/template/cache/` to accelerate subsequent runs.
- 🚀 **Pre-Configured Image Customization:** Uses `virt-customize` on the host to inject dependencies (`perl`, `wget`, `curl`, `qemu-guest-agent`) and a background cPanel installer systemd service into the OS.
- 🌐 **Native Cloud-Init Setup:** Configures static IP CIDR prefix, Gateway, Nameservers, and Root password options (including random generation) via Proxmox Native Cloud-Init.
- 🛡️ **Safety Check suite:** Built-in verification for root execution, Proxmox VE environment version (PVE 8/9 support), CPU architectures (`amd64` check), active SSH sessions, and duplicate VM IDs.

---

## Prerequisites

1. **Proxmox VE Host:** Must be executed directly on a Proxmox VE hypervisor host shell as `root`.
2. **Architecture:** Host machine must run on `amd64` architecture.
3. **Networking:** A free static IPv4 address, matching subnet CIDR, Gateway IP, and a fully qualified domain name (FQDN) mapping to the static IP (cPanel licensing requirement).
4. **License:** A valid cPanel license associated with the VM's static IP.

---

## Installation & Usage

Run the following command directly in the shell of your Proxmox VE host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/7ussainnabeel/Proxmox-cPanel/main/vm/cpanel.sh)"
```

*Or run from a cloned repository local folder:*
```bash
git clone https://github.com/7ussainnabeel/Proxmox-cPanel.git
cd Proxmox-cPanel
bash vm/cpanel.sh
```

---

## Configuration Settings

During execution, the wizard will walk you through setting up:

| Setting | Default | Description |
| :--- | :--- | :--- |
| **VM ID** | *Next ID* | Unique Proxmox Virtual Machine identifier. |
| **Machine Type** | `q35` | Modern PCIe/Q35 machine profile (recommended) or legacy i440fx. |
| **Disk Size** | `100G` | Disk size allocated for hosting directories (resizes automatically). |
| **Disk Cache** | `None` | Storage cache settings (None or Write-Through). |
| **CPU Model** | `Host` | Virtual CPU type (Host or KVM64). Host profile is highly recommended. |
| **CPU Cores** | `4` | Cores assigned to VM. |
| **RAM** | `8192` | Memory allocated to the VM (in MB). |
| **Network Bridge** | `vmbr0` | Network bridge interface name. |
| **FQDN Hostname** | *(Required)* | Fully qualified domain name (e.g., `cpanel.example.com`). |
| **Static IPv4** | *(Required)* | Static IP to assign (CIDR format required: `x.x.x.x/xx`). |
| **Gateway** | *(Required)* | Gateway address for internet access. |
| **DNS Servers** | `1.1.1.1 8.8.8.8` | DNS resolvers. |
| **Root Password** | *(Required)* | User password for root login (interactive prompt or random generator). |

---

## How It Works Under the Hood

1. **Pre-flight Checks:** Verifies hypervisor OS, `root` privileges, and CPU platform support.
2. **Resource Selection:** Prompts user configurations via whiptail dialog lists.
3. **Storage pool extraction:** Queries available storage destinations and asks the user to select one.
4. **Custom Image Provisioning:**
   - Checks for `libguestfs-tools` (installs it on Proxmox if missing).
   - Injects `/root/install-cpanel.sh` and `/etc/systemd/system/install-cpanel.service` into the disk image.
5. **VM Provisioning:**
   - Creates the Proxmox VM, imports and resizes the customized disk.
   - Attaches and configures the native Cloud-Init drive with static IP, Hostname, and password configs.
6. **First Boot Installation:**
   - When the VM starts, Cloud-Init applies network and login configurations.
   - The first-boot systemd service runs the cPanel installation in the background, updating repositories and pulling down the latest WHM binary files.

---

## Accessing cPanel & WHM

Once VM deployment finishes, the cPanel setup will continue running in the background for **15–40 minutes**. You can access and monitor it as follows:

### Web Portals
- **WHM (Web Host Manager):** `https://<YOUR_VM_IP>:2087`
- **cPanel (Client Portal):** `https://<YOUR_VM_IP>:2083`

### Monitoring Progress
Log into the VM via SSH or the Proxmox Console as `root` using your chosen password and view the live log output:

```bash
tail -f /var/log/cpanel-install.log
```

---

## License / Disclaimer
This script is provided as-is without warranties. Ensure you obtain appropriate licenses from cPanel to run these products.
