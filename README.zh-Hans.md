# CMCC PZ-L8 OpenWrt 固件

[English](README.md)

为中国移动 PZ-L8 路由器编译的带 Wi-Fi 支持的 OpenWrt 固件，提供两种版本：
* **AP 模式** — 适用于接入点部署
* **路由模式** — 适用于主路由使用

## 固件版本对比

| 特性 | AP 模式 | 路由模式 |
|------|---------|----------|
| **用途** | 接入点 / Mesh 节点 | 主路由 |
| **网口** | 全部桥接（lan1-3、wan） | WAN + LAN 分离 |
| **DHCP 服务** | ❌ 无 | ✅ 有（dnsmasq） |
| **防火墙** | ❌ 无 | ✅ 有（firewall4） |
| **PPPoE 拨号** | ❌ 无 | ✅ 有 |
| **IPv6** | SLAAC 客户端 | 完整支持（odhcp6c + odhcpd） |
| **Mesh（802.11s）** | ✅ 有 + usteer | ❌ 无 |
| **LuCI 界面** | 精简版 | 完整版 |

## 硬件规格

| 组件 | 规格 |
|------|------|
| SoC | 高通 IPQ5018（双核 Cortex-A53） |
| 内存 | 256MB |
| 闪存 | 128MB NAND |
| WiFi 2.4GHz | IPQ5018（SoC 内置） |
| WiFi 5GHz | QCN6102 |
| 网口 | 4 × 千兆（lan1、lan2、lan3、wan） |

---

## AP 模式

针对接入点部署优化。所有以太网口桥接在一起，作为透明 AP 工作。适合扩展现有网络覆盖或构建 Mesh 网络。

### 功能特性

- **全端口桥接** — lan1、lan2、lan3、wan 桥接为 `br-lan`
- **Mesh 组网** — 支持 802.11s mesh，配合 usteer 实现无缝漫游
- **IPv6 支持** — 通过 SLAAC 自动获取 IPv6 地址
- **精简体积** — 无防火墙、DHCP、路由等额外开销

### 默认网络

- **IPv4**：DHCP 客户端（自动从主路由获取 IP）
- **IPv4 兜底**：192.168.10.1（DHCP 获取失败时使用）
- **IPv6**：通过 SLAAC 自动获取
- **访问地址**：http://[设备IP] 或 http://192.168.10.1

---

## 路由模式

全功能路由固件，支持 WAN/LAN 分离、防火墙和 PPPoE 拨号。

### 功能特性

- **完整路由功能** — NAT、防火墙、DHCP 服务
- **PPPoE 拨号** — 直接连接运营商
- **完整 IPv6 支持** — DHCPv6-PD、RA、NAT66
- **完整 LuCI** — 全功能 Web 管理界面

### 默认网络

- **WAN**：wan 口（DHCP 或 PPPoE 客户端）
- **LAN**：lan1、lan2、lan3 桥接为 `br-lan`
- **LAN IP**：192.168.1.1
- **DHCP**：LAN 口已启用

## 下载

从 [Releases](https://github.com/CrazyBoyFeng/openwrt-pz-l8/releases) 或 [Actions 构建产物](https://github.com/CrazyBoyFeng/openwrt-pz-l8/actions)下载。

---

## 本地编译

无需 GitHub 账号。`build.sh` 脚本自动化执行与 CI 工作流相同的构建步骤。

### 前提条件

- **Linux**（Debian/Ubuntu、Fedora、Arch、Alpine）或 **macOS**（需 Homebrew）
- **Windows**：使用 WSL2
- 约 25 GB 可用磁盘空间
- 内存至少 4 GB（推荐 8 GB）
- 网络连接

### 快速开始

```bash
git clone https://github.com/CrazyBoyFeng/openwrt-pz-l8.git
cd openwrt-pz-l8

# 编译全部变种（router + ap）
./build.sh

# 仅编译单个变种
./build.sh router
./build.sh ap
```

### 选项

| 选项 | 说明 |
|------|------|
| `-c on\|off` | 启用/禁用 ccache（默认：on） |
| `-j N` | 并行编译任务数（默认：nproc） |
| `-k PATH` | 复用已有 OpenWrt 源码目录（跳过克隆） |
| `-h` | 显示帮助 |

### 示例

```bash
./build.sh -j 2 ap                # 使用 2 个任务编译 ap
./build.sh -k ~/openwrt router    # 复用已有 OpenWrt 源码目录
./build.sh -c off router ap       # 不使用 ccache 编译
```

构建产物放在 `artifacts/<variant>/` 目录下。

---

## 安装

> **注意**：如果设备仍在运行原厂固件，必须先刷入 `factory.ubi` 或 `initramfs.itb` 镜像。刷写方法请参考 [PR #20681](https://github.com/openwrt/openwrt/pull/20681) 的安装指南。安装 OpenWrt 后，后续升级可使用 `sysupgrade.bin` 镜像。

### 前提条件

- 升级（sysupgrade.bin）需设备已运行 OpenWrt
- 可访问 LuCI Web 界面或 SSH

### 通过 LuCI Web 界面

1. 进入 **系统** → **备份/刷写固件**
2. 在"刷写新固件"下点击 **选择文件**
3. 选择 `sysupgrade.bin` 文件
4. 点击 **上传** 并确认刷写
5. 等待设备重启（约 2-3 分钟）

### 通过 SSH

```bash
# 传输固件到设备
scp openwrt-qualcommax-ipq50xx-cmcc_pz-l8-squashfs-sysupgrade.bin root@[设备IP]:/tmp/

# 刷写固件
ssh root@[设备IP]
sysupgrade -n /tmp/openwrt-qualcommax-ipq50xx-cmcc_pz-l8-squashfs-sysupgrade.bin
```

`-n` 参数不会保留配置文件。如需保留当前设置，请去掉 `-n`。

---

## 安装语言包

固件默认语言为英文。

### 通过 LuCI

1. 进入 **系统** → **软件包**
2. 点击 **更新列表**
3. 搜索并安装以下软件包：
   - `luci-i18n-base-zh-cn`
   - `luci-i18n-package-manager-zh-cn`
4. 进入 **系统** → **语言**，选择中文

### 通过 SSH

```bash
apk update
apk add luci-i18n-base-zh-cn luci-i18n-package-manager-zh-cn
```

### 其他语言包

- **路由模式**：安装 `luci-i18n-firewall-zh-cn` 获取防火墙界面中文翻译
- **AP 模式**：安装 `luci-i18n-usteer-zh-cn` 获取 usteer 漫游界面中文翻译

---

## 技术细节

### 补丁 [PR #21495](https://github.com/openwrt/openwrt/pull/21495)

- CMCC PZ-L8 设备支持
- ath11k-smallbuffers：针对 256MB 内存设备优化的 WiFi 驱动，减小缓冲区大小以降低内存占用

### 补丁 FM25LS01 支持

后批次的 CMCC PZ-L8（V2 版本）使用了 FMSH FM25LS01 SPI NAND 闪存芯片，替代了早期批次中的 ESMT F50D1G41LB。
FM25LS01 驱动尚未被上游 Linux 内核或 OpenWrt 收录。
本项目通过从 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt/blob/cec44a8d851230dff1807d616f264593f4fa13ae/target/linux/generic/hack-6.12/400-mtd-spinand-Support-fmsh.patch#L187-L195) 适配的补丁来添加支持，该补丁源自 Rockchip BSP 代码。
经与 [FM25LS01 规格书](https://www.fmsh.com/nvm/FM25LS01_ds_eng.pdf) 核对，ImmortalWrt 补丁的所有参数均与芯片规格一致。

| 规格 | 值 |
|------|-----|
| JEDEC ID | `0xA5` |
| 容量 | 128MiB |
| 页大小 | 2048 字节 |
| OOB 大小 | 128 字节 |
| On-die ECC | 1 位 / 512 字节 |
| **补丁 ECC** | **8 位 / 512 字节** |

#### 补丁 ECC

FM25LS01 规格每 512 字节数据需 1-bit on-die ECC。  
但 U-Boot 引导加载程序（Qualcomm QPIC NAND 控制器）使用 8-bit ECC 写入 NAND 数据，与 Linux `qcom_snand` 控制器驱动不兼容。这会导致 `ubiattach` 失败（错误 `-74 EUCLEAN`）及刷机后设备变砖。  
因此，补丁将 ECC 声明改为 `NAND_ECCREQ(8, 512)` 以匹配 U-Boot 的行为。这是针对 `qcom_snand` 驱动无法协调芯片 on-die ECC 规格与控制器实际 ECC 强度的设备级临时修复。  
更好的方案是向 Linux `qcom_snand` 控制器驱动提交补丁，使其能独立于芯片的 `NAND_ECCREQ` 声明来处理 ECC 强度。

虽然此补丁不符合芯片规格，但不会产生负面影响。

### WiFi Board Data 文件

- **来源**：[firmware_qca-wireless PR #106](https://github.com/openwrt/firmware_qca-wireless/pull/106)
- **提取自**：CMCC PZ-L8 官方固件 501.11
- **安装到**：
  - `/lib/firmware/ath11k/IPQ5018/hw1.0/board-2.bin`
  - `/lib/firmware/ath11k/QCN6122/hw1.0/board-2.bin`

---

## 项目结构

```
build.sh                         # 主构建脚本（本地编译和 CI 共用）
variants/
  ap/
    build.config                # AP 模式：完整构建配置（目标、WiFi、Mesh、精简 LuCI）
    etc/uci-defaults/
      99-init-ap                 # 初始化 AP 模式配置（已设主机名或密码则跳过）
    etc/sysctl.d/
      99-ap-ipv6.conf            # AP 桥接模式 sysctl：接受上游 IPv6 RA
  router/
    build.config                # 路由模式：完整构建配置（目标、WiFi、防火墙、完整 LuCI）
patches/
  001-fm25ls01-support.patch    # FM25LS01 SPI NAND 支持（V2 硬件）
  002-pz-l8-caldata.patch        # PZ-L8 ath11k caldata 配置（MAC、regdomain、macflag）
.github/
  workflows/build.yml           # CI 构建工作流（调用 build.sh）
  release-notes.md              # 发布说明模板
```

### 自定义版本

添加新的构建版本（例如"服务器"模式）：

1. 创建 `variants/server/build.config`，填入所需的软件包（可复制现有配置作为模板）
2. 创建 `variants/server/etc/uci-defaults/`，放入首次启动脚本
3. 无需其他修改 — `build.sh` 会自动扫描 `variants/*/build.config` 发现新版本

---

## 常见问题

### 无法访问设备（AP 模式）

1. 检查设备是否通过 DHCP 获取了 IP
2. 尝试兜底 IP：192.168.10.1（使用 192.168.10.x 网段的静态 IP 直连）
3. 检查 IPv6 地址：`ip -6 addr show br-lan`

### 无法访问设备（路由模式）

1. 连接到 LAN 口
2. 将电脑 IP 设置为 192.168.1.x 网段
3. 访问 http://192.168.1.1

### 内存不足

如果设备频繁崩溃或断连，可能是内存不足。可以尝试以下方案：

#### 降低日志级别

降低系统日志级别可以节省内存：

```bash
uci set system.@system[0].log_level='4'
uci commit system
/etc/init.d/log restart
```

#### 优化 Zram

增大 zram 大小并使用 zstd 压缩以提高内存利用率：

```bash
# 启用 zstd 压缩，设置大小为 180MB
uci set system.@system[0].zram_comp_algo='zstd'
uci set system.@system[0].zram_size_mb='180'
uci commit system
reboot
```

> **注意**：ZSTD 压缩已内置于内核（非独立模块），无需额外安装软件包。zstd 的压缩率优于默认的 lzo，但 CPU 占用更高。

```bash
# 查看内存使用情况
free -m
```

---

## 许可证

本项目遵循与 OpenWrt 相同的许可条款。OpenWrt 由多个组件组成，使用各种开源许可证，包括 GPL-2.0、GPL-2.0+、LGPL-2.1、MIT、ISC 和 BSD 许可证。具体许可证信息请参见各软件包。

更多 OpenWrt 许可证信息请参见：https://openwrt.org/docs/guide-developer/license
