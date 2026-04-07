# OpenWrt Firmware for CMCC PZ-L8

Custom OpenWrt firmware for CMCC PZ-L8 router with two variants:
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
| **PHY-to-PHY 2Gbps** | ❌ No | ✅ Yes (PR #21496) |
| **LuCI** | Minimal | Full |
| **RAM Optimization** | ath11k-smallbuffers | ath11k-smallbuffers |

## Hardware Specifications

| Component | Specification |
|-----------|---------------|
| SoC | Qualcomm IPQ5000 (Dual-core Cortex-A53) |
| RAM | 256MB |
| Flash | 128MB NAND |
| WiFi 2.4GHz | IPQ5000 (SoC built-in) |
| WiFi 5GHz | QCN6102 |
| Ethernet | 4x Gigabit (lan1, lan2, lan3, wan) |

---

## AP Mode

Optimized for access point deployment. All Ethernet ports are bridged together, acting as a transparent AP. Ideal for extending existing network coverage or building mesh networks.

### Features

- **All Ports Bridged** - lan1, lan2, lan3, wan bridged as `br-lan`
- **Mesh Networking** - 802.11s mesh support with usteer for seamless roaming
- **IPv6 Support** - Automatic IPv6 address via SLAAC
- **Low Memory Optimization** - ath11k-smallbuffers driver for 256MB RAM
- **Minimal Footprint** - No firewall, DHCP, or routing overhead

### Default Network

- **IPv4**: DHCP client (automatic IP from main router)
- **IPv4 Fallback**: 192.168.10.1 (if DHCP fails)
- **IPv6**: Automatic via SLAAC
- **Access**: http://[device-ip] or http://192.168.10.1

---

## Router Mode

Full-featured router firmware with WAN/LAN separation, firewall, and PPPoE support. Includes PHY-to-PHY CPU link patch for 2Gbps throughput.

### Features

- **Full Router Functions** - NAT, firewall, DHCP server
- **PPPoE Support** - Direct ISP connection
- **IPv6 Full Support** - DHCPv6-PD, RA, NAT66
- **2Gbps Throughput** - PHY-to-PHY CPU link (PR #21496)
- **Complete LuCI** - Full web management interface

### Default Network

- **WAN**: wan port (DHCP or PPPoE client)
- **LAN**: lan1, lan2, lan3 bridged as `br-lan`
- **LAN IP**: 192.168.1.1
- **DHCP**: Enabled on LAN

## Download

Download from [Releases](https://github.com/CrazyBoyFeng/openwrt-pz-l8/releases) or [Actions artifacts](https://github.com/CrazyBoyFeng/openwrt-pz-l8/actions).

---

## Installation

> **Note**: This repository does not provide factory images. You must first flash the official OpenWrt factory firmware following the guide at [PR #20681](https://github.com/openwrt/openwrt/pull/20681), then upgrade to this repository's sysupgrade image.

### Prerequisites

- Device must already be running OpenWrt
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

### Patches Applied

| Patch | AP Mode | Router Mode | Description |
|-------|---------|-------------|-------------|
| [PR #21495](https://github.com/openwrt/openwrt/pull/21495) | ✅ | ✅ | Device support + ath11k-smallbuffers |
| [PR #21496](https://github.com/openwrt/openwrt/pull/21496) | ❌ | ✅ | PHY-to-PHY CPU link for 2Gbps |

### WiFi Board Data Files

- **Source**: [firmware_qca-wireless PR #106](https://github.com/openwrt/firmware_qca-wireless/pull/106)
- **Extracted from**: Official CMCC PZ-L8 firmware 501.11
- **Installed to**:
  - `/lib/firmware/ath11k/IPQ5018/hw1.0/board-2.bin`
  - `/lib/firmware/ath11k/QCN6122/hw1.0/board-2.bin`

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

## Credits

- OpenWrt Project - https://openwrt.org
- PR #21495 contributors - Device support + ath11k-smallbuffers
- PR #21496 contributors - PHY-to-PHY CPU link
- BDF files from firmware_qca-wireless PR #106 by sqliuchang

## License

This project is licensed under the same terms as OpenWrt. OpenWrt is composed of many components that are licensed under various open source licenses, including GPL-2.0, GPL-2.0+, LGPL-2.1, MIT, ISC, and BSD licenses. See individual packages for specific license information.

For more information about OpenWrt licensing, see: https://openwrt.org/docs/guide-developer/license
