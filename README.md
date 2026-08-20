# Proxmox cPanel & WHM VM Installer

A lightweight, automated Bash script to deploy a fully configured AlmaLinux 9 KVM Virtual Machine on Proxmox VE, automatically installing **cPanel & WHM**.

The script leverages **Cloud-Init** for seamless networking, hostname provisioning, OS optimization, and background installation of cPanel/WHM.

---

## Features

- 🖥️ **Automated VM Creation:** Creates a Proxmox VM with optimal hardware specifications for hosting cPanel/WHM (q35 machine, host CPU type, VirtIO SCSI Single, VirtIO Net interface).
- 💿 **AlmaLinux 9 Cloud Image:** Downloads and imports the official AlmaLinux 9 Generic Cloud image.
- ⚙️ **Cloud-Init Integration:** Configures system hostname, static IP networking, DNS, SSH, and password authentication dynamically.
- 🚀 **cPanel Installer Bootstrapping:** Automates OS prerequisites (disabling SELinux, disabling firewalld, updating DNF, installing perl/wget/curl) and kicks off the official cPanel installation process.
- 🔍 **Safety & Validation:** Validates Proxmox storage, network bridge existence, CIDR notation, hostname FQDN, and ensures the VM ID is not already in use before starting.

---

## Prerequisites

1. **Proxmox VE Host:** Must be executed directly on a Proxmox VE hypervisor shell as `root`.
2. **Tools Installed:** Requires `wget` on the Proxmox host.
3. **Network Configurations:** A free static IPv4 address, matching CIDR subnet prefix, gateway, and DNS servers.
4. **Valid FQDN:** A fully qualified domain name pointing to the static IP (e.g., `cpanel.yourdomain.com`).
5. **cPanel License:** A valid license associated with the public IP (or trial license).

---

## Installation & Usage

1. Log into your Proxmox VE node via SSH or console as `root`.
2. Clone this repository or download the installer script:
   ```bash
   git clone https://github.com/7ussainnabeel/Proxmox-cPanel.git
   cd Proxmox-cPanel
   ```
3. Run the installer:
   ```bash
   bash vm/cpanel.sh
   ```
4. Follow the interactive CLI prompts to configure your VM.

---

## Configuration Settings

During execution, the script will prompt you for the following options:

| Setting | Default Value | Description |
| :--- | :--- | :--- |
| **VM ID** | `130` | Unique identifier for the VM in Proxmox. |
| **VM Name** | `cpanel` | Friendly name of the VM. |
| **CPU Cores** | `4` | Number of CPU cores allocated (host CPU type). |
| **RAM** | `8192` | Memory allocated to the VM (in MB). |
| **Disk Size** | `100` | Disk size allocated in Gigabytes (resized automatically). |
| **Proxmox Storage** | `local-lvm` | Target Proxmox storage name where the disk will be placed. |
| **Network Bridge** | `vmbr0` | Proxmox network bridge interface. |
| **Static IPv4** | *(Required)* | The static IP address to assign to the virtual machine. |
| **CIDR Prefix** | *(Required)* | Subnet mask in CIDR format (e.g., `24` for `255.255.255.0`). |
| **Gateway** | *(Required)* | Gateway IP address for VM internet access. |
| **DNS Server 1** | `1.1.1.1` | Primary DNS resolver inside the VM. |
| **DNS Server 2** | `8.8.8.8` | Secondary DNS resolver inside the VM. |
| **FQDN Hostname** | *(Required)* | Fully qualified domain name (e.g., `cpanel.example.com`). |

---

## How It Works

1. **Pre-checks:** Verifies the user is `root` and that Proxmox CLI tools (`qm`, `pvesm`) are present.
2. **Validation:** Checks if storage exists, and validates the IP formatting and hostname formatting.
3. **Cloud Image Retrieval:** Downloads the official AlmaLinux 9 Generic Cloud image to `/tmp/`.
4. **Cloud-Init Generation:** Writes a YAML configuration file to provision the root user and execute the cPanel installation script.
5. **VM Provisioning:**
   - Registers a VM with the selected ID and resources.
   - Imports the downloaded AlmaLinux image to the Proxmox storage.
   - Attaches and resizes the disk dynamically.
   - Maps the network bridge and static IP configuration.
6. **Initialization:** Starts the VM and waits for the static IP to respond to ping requests.
7. **Post-Boot Execution:** Inside the VM, AlmaLinux boots up and Cloud-Init triggers `/root/install-cpanel.sh`. This:
   - Disables SELinux and Firewalld.
   - Performs a DNF update and installs dependencies.
   - Downloads and runs the official cPanel installation installer (`sh latest`) in the background.

---

## Accessing cPanel & WHM

Once the installation inside the VM begins (usually takes 15–40 minutes depending on disk speed and internet bandwidth), you can monitor its progress or log into cPanel & WHM.

### Web Interfaces
- **WHM (Web Host Manager):** `https://<YOUR_VM_IP>:2087`
- **cPanel (Client Portal):** `https://<YOUR_VM_IP>:2083`

> [!NOTE]
> Since the installation runs via Cloud-Init in the background after the VM starts, the web ports will not be accessible immediately. 

### Monitoring Installation Progress
To track the progress of the cPanel installation, log into your new VM (via SSH or the Proxmox Console) as `root` and check the log files:

```bash
# View Cloud-Init output log (shows OS setup status)
tail -f /var/log/cloud-init-output.log

# View cPanel installation logs directly
tail -f /var/log/cpanel-install.log
```

---

## License / Disclaimer
This script is provided as-is without any warranties. Please make sure you have appropriate licenses to run cPanel/WHM.
