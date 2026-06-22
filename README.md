# OpenWrt Firmware for CMCC PZ-L8

[简体中文](README.zh-Hans.md)

OpenWrt firmware with Wi-Fi support for CMCC PZ-L8 router, available in two variants:
* **AP Mode** for access point deployment
* **Router Mode** for main router usage

## Firmware Variants

| Feature | AP Mode | Router Mode |
|---------|---------|-------------|
| **Purpose** | Access Point / Mesh Node | Main Router |
| **Network Ports** | All bridged (lan1-3, wan) | WAN + LAN separated |
| **DHCP Server** | ❌ No | ✅ Yes (dnsmasq) |
| **Firewall** | ❌ No | ✅ Yes (firewall4) |
| **PPPoE Support** | ❌ No | ✅ Yes |
| **IPv6** | SLAAC client | Full (odhcp6c + odhcpd) |
| **Mesh (802.11s)** | ✅ Yes + usteer | ❌ No |
| **LuCI** | Minimal | Full |

## Hardware Specifications

| Component | Specification |
|-----------|---------------|
| SoC | Qualcomm IPQ5018 (Dual-core Cortex-A53) |
| RAM | 256MB |
| Flash | 128MB NAND |
| WiFi 2.4GHz | IPQ5018 (SoC build-in) |
| WiFi 5GHz | QCN6102 |
| Ethernet | 4x Gigabit (lan1, lan2, lan3, wan) |

---

## AP Mode

Optimized for access point deployment. All Ethernet ports are bridged together, acting as a transparent AP. Ideal for extending existing network coverage or building mesh networks.

### Features

- **All Ports Bridged** - lan1, lan2, lan3, wan bridged as `br-lan`
- **Mesh Networking** - 802.11s mesh support with usteer for seamless roaming
- **IPv6 Support** - Automatic IPv6 address via SLAAC
- **Minimal Footprint** - No firewall, DHCP, or routing overhead

### Default Network

- **IPv4**: DHCP client (automatic IP from main router)
- **IPv4 Fallback**: 192.168.10.1 (if DHCP fails)
- **IPv6**: Automatic via SLAAC
- **Access**: http://[device-ip] or http://192.168.10.1

---

## Router Mode

Full-featured router firmware with WAN/LAN separation, firewall, and PPPoE support.

### Features

- **Full Router Functions** - NAT, firewall, DHCP server
- **PPPoE Support** - Direct ISP connection
- **IPv6 Full Support** - DHCPv6-PD, RA, NAT66
- **Complete LuCI** - Full web management interface

### Default Network

- **WAN**: wan port (DHCP or PPPoE client)
- **LAN**: lan1, lan2, lan3 bridged as `br-lan`
- **LAN IP**: 192.168.1.1
- **DHCP**: Enabled on LAN

## Download

Download from [Releases](https://github.com/CrazyBoyFeng/openwrt-pz-l8/releases) or [Actions artifacts](https://github.com/CrazyBoyFeng/openwrt-pz-l8/actions).

---

## Building Locally

No GitHub account required. The `build.sh` script automates the same steps as the CI workflow.

### Prerequisites

- **Linux** (Debian/Ubuntu, Fedora, Arch, Alpine) or **macOS** (with Homebrew)
- **Windows**: use WSL2
- ~25 GB free disk space
- 4 GB RAM minimum (8 GB recommended)
- Internet connection

### Quick Start

```bash
git clone https://github.com/CrazyBoyFeng/openwrt-pz-l8.git
cd openwrt-pz-l8

# Build all variants (router + ap)
./build.sh

# Build only one variant
./build.sh router
./build.sh ap
```

### Options

| Option | Description |
|--------|-------------|
| `-c on\|off` | Enable/disable ccache (default: on) |
| `-j N` | Number of parallel build jobs (default: nproc) |
| `-k PATH` | Reuse existing OpenWrt source tree (skip clone) |
| `-h` | Show help |

### Examples

```bash
./build.sh -j 2 ap                # build ap with 2 jobs
./build.sh -k ~/openwrt router    # reuse existing OpenWrt tree
./build.sh -c off router ap       # build without ccache
```

Artifacts are placed in `artifacts/<variant>/`.

---

## Installation

> **Note**: If your device is still running the stock firmware, you must flash the `factory.ubi` or `initramfs.itb` image first. Please follow the installation guide at [PR #20681](https://github.com/openwrt/openwrt/pull/20681) for the flashing method. Once OpenWrt is installed, you can use the `sysupgrade.bin` image for subsequent upgrades.

### Prerequisites

- Device must already be running OpenWrt (if upgrading with sysupgrade.bin)
- Access to LuCI web interface or SSH

### Via LuCI Web Interface

1. Navigate to **System** → **Backup / Flash Firmware**
2. Under "Flash new firmware image", click **Choose File**
3. Select the `sysupgrade.bin` file
4. Click **Upload** and confirm the flash
5. Wait for the device to reboot (approximately 2-3 minutes)

### Via SSH

```bash
# Transfer firmware to device
scp openwrt-qualcommax-ipq50xx-cmcc_pz-l8-squashfs-sysupgrade.bin root@[device-ip]:/tmp/

# Flash firmware
ssh root@[device-ip]
sysupgrade -n /tmp/openwrt-qualcommax-ipq50xx-cmcc_pz-l8-squashfs-sysupgrade.bin
```

The `-n` flag will not preserve configuration files. Omit it to keep your current settings.

---

## Installing Language Packs

The firmware comes with English as the default language.

### Via LuCI

1. Navigate to **System** → **Software**
2. Click **Update lists**
3. Search for and install the following packages:
   - `luci-i18n-base-zh-cn`
   - `luci-i18n-package-manager-zh-cn`
4. Navigate to **System** → **Language** and select Chinese

### Via SSH

```bash
apk update
apk add luci-i18n-base-zh-cn luci-i18n-package-manager-zh-cn
```

### Additional Language Packs

- **Router Mode**: Install `luci-i18n-firewall-zh-cn` for firewall interface translation
- **AP Mode**: Install `luci-i18n-usteer-zh-cn` for usteer roaming interface translation

---

## Technical Details

### Patch [PR #21495](https://github.com/openwrt/openwrt/pull/21495)

- CMCC PZ-L8 device support
- ath11k-smallbuffers: optimized WiFi driver for 256MB RAM devices, reduces buffer sizes to lower memory usage

### Patch FM25LS01 Support

Later batches (V2) of the CMCC PZ-L8 use the FMSH FM25LS01 SPI NAND flash chip instead of the ESMT F50D1G41LB used in earlier batches.  
The FM25LS01 driver is not yet included in the upstream Linux kernel or OpenWrt.  
This project adds support via a patch adapted from [ImmortalWrt](https://github.com/immortalwrt/immortalwrt/blob/cec44a8d851230dff1807d616f264593f4fa13ae/target/linux/generic/hack-6.12/400-mtd-spinand-Support-fmsh.patch#L187-L195), which in turn originates from Rockchip BSP code.  
The ImmortalWrt patch has been verified against the [FM25LS01 datasheet](https://www.fmsh.com/nvm/FM25LS01_ds_eng.pdf), all parameters match the chip specification.

| Specification | Value |
|---------------|-------|
| JEDEC ID | `0xA5` |
| Capacity | 128MiB |
| Page size | 2048 bytes |
| OOB size | 128 bytes |
| On-die ECC | 1 bit / 512 bytes|
| **Patched ECC** | **8 bits / 512 bytes** |

#### Patched ECC

The FM25LS01 specifies 1-bit on-die ECC per 512 bytes.  
However, the U-Boot bootloader (Qualcomm QPIC NAND controller) writes NAND data with 8-bit ECC, which is incompatible with the the Linux `qcom_snand` controller driver. This results in `ubiattach` failures (error `-74 EUCLEAN`) and device bricks after flashing.  
Therefore, the patch declares `NAND_ECCREQ(8, 512)` to match U-Boot's behavior. This is a device-specific workaround for the `qcom_snand` driver's inability to reconcile the chip's on-die ECC specification with the controller's actual ECC strength.  
A better solution would be to submit a patch to the Linux `qcom_snand` controller driver so that it can handle ECC strength independently of the chip's `NAND_ECCREQ` declaration.

Although this patch does not comply with the chip specifications, it has no negative effects.  

### WiFi Board Data Files

- **Source**: [firmware_qca-wireless PR #106](https://github.com/openwrt/firmware_qca-wireless/pull/106)
- **Extracted from**: Official CMCC PZ-L8 firmware 501.11
- **Installed to**:
  - `/lib/firmware/ath11k/IPQ5018/hw1.0/board-2.bin`
  - `/lib/firmware/ath11k/QCN6122/hw1.0/board-2.bin`

---

## Project Structure

```
build.sh                         # Main build script (shared by local and CI builds)
variants/
  ap/
    build.config                # AP mode: full build config (target, WiFi, mesh, minimal LuCI)
    etc/uci-defaults/
      99-init-ap                 # Initial AP mode config (skip if hostname or password set)
    etc/sysctl.d/
      99-ap-ipv6.conf            # AP bridge mode sysctl: accept upstream IPv6 RA
  router/
    build.config                # Router mode: full build config (target, WiFi, firewall, full LuCI)
patches/
  kernel/
    440-v6.12-mtd-spinand-add-support-for-FudanMicro-FM25LS01.patch    # FM25LS01 SPI NAND support for V2 hardware (affects compilation)
  openwrt/
    001-pz-l8-caldata.patch        # PZ-L8 ath11k caldata entries (affects rootfs only)
.github/
  workflows/build.yml           # CI build workflow (calls build.sh)
  release-notes.md              # Release notes template
```

### Custom Variant

To add a new build variant (e.g., "Server" mode):

1. Create `variants/server/build.config` with the desired packages (copy an existing config as template)
2. Create `variants/server/etc/uci-defaults/` with any first-boot scripts
3. No other changes needed — `build.sh` auto-discovers variants by scanning `variants/*/build.config`

---

## Troubleshooting

### Cannot Access Device (AP Mode)

1. Check if device obtained IP via DHCP
2. Try fallback IP: 192.168.10.1 (connect directly with static IP in 192.168.10.x range)
3. Check IPv6 address: `ip -6 addr show br-lan`

### Cannot Access Device (Router Mode)

1. Connect to LAN port
2. Set computer IP to 192.168.1.x range
3. Access http://192.168.1.1

### Memory Issues

If you experience frequent crashes or disconnections, the device may be running low on memory. Try the following solutions:

#### Reduce Log Level

Lowering the system log level can save memory:

```bash
uci set system.@system[0].log_level='4'
uci commit system
/etc/init.d/log restart
```

#### Optimize Zram

Increase zram size and use zstd compression for better memory efficiency:

```bash
# Enable zstd compression and set size to 180MB
uci set system.@system[0].zram_comp_algo='zstd'
uci set system.@system[0].zram_size_mb='180'
uci commit system
reboot
```

> **Note**: ZSTD compression is built into the kernel (not a separate module), so no additional package installation is needed. zstd provides better compression ratio than default lzo, but consumes more CPU.

```bash
# Check memory usage
free -m
```

---

## License

This project is licensed under the same terms as OpenWrt. OpenWrt is composed of many components that are licensed under various open source licenses, including GPL-2.0, GPL-2.0+, LGPL-2.1, MIT, ISC, and BSD licenses. See individual packages for specific license information.

For more information about OpenWrt licensing, see: https://openwrt.org/docs/guide-developer/license
