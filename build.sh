#!/usr/bin/env bash
# Build script for CMCC PZ-L8 OpenWrt firmware
#
# Shared by both local and CI builds:
#   - Local:  run directly with ./build.sh
#   - CI:     called by .github/workflows/build.yml (uses -k for pre-checked-out tree)
#
# Prerequisites:
#   - Linux (Debian/Ubuntu, Fedora, Arch) or macOS
#   - Windows: use WSL2
#   - ~25 GB free disk space
#   - 4 GB RAM minimum (8 GB recommended)
#   - Internet connection
#
# Usage:
#   ./build.sh                    # build all auto-discovered variants
#   ./build.sh router             # build only router variant
#   ./build.sh ap                 # build only ap variant
#   ./build.sh -c                 # build with ccache (default)
#   ./build.sh -c off             # build without ccache
#   ./build.sh -j 4               # use 4 parallel jobs (default: nproc)
#   ./build.sh -k /path/to/openwrt # reuse existing OpenWrt source tree
#   ./build.sh -h                 # show help
#
# Artifacts are placed in: artifacts/<variant>/

set -euo pipefail

# ── Locate project root ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# ── Configuration (must match .github/workflows/build.yml) ──────────────
TARGET="qualcommax"
SUBTARGET="ipq50xx"
DEVICE="cmcc_pz-l8"

# Auto-discover variants: scan variants/*/build.config
# Directory name = variant name. No hardcoded list needed.
DEFAULT_VARIANTS=""
for _d in "$PROJECT_ROOT/variants"/*/; do
    _v="$(basename "$_d")"
    [ -f "$_d/build.config" ] && DEFAULT_VARIANTS="$DEFAULT_VARIANTS $_v"
done
DEFAULT_VARIANTS="${DEFAULT_VARIANTS# }"
if [ -z "$DEFAULT_VARIANTS" ]; then
    echo "ERROR: No variants found. Create variants/<name>/build.config files."
    exit 1
fi

PR_21495_SHA="5e6237857bbce445a274185383b2fd8affb81e33"
BDF_COMMIT="f7ad5fee1924efdb5d8b2d1bf95bd3867d22e701"
OPENWRT_REPO="https://github.com/openwrt/openwrt.git"
OPENWRT_BRANCH="main"
OPENWRT_SHA="4a0e6aa95c122cb33c7828fd27ea0dbf56abca5c"

# ── Defaults ─────────────────────────────────────────────────────────────
VARIANTS="${DEFAULT_VARIANTS}"
JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
USE_CCACHE="on"
OPENWRT_DIR=""

# ── Parse arguments ─────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [VARIANT...]

Build OpenWrt firmware for CMCC PZ-L8 locally.

Variants (auto-discovered from variants/*/build.config):
  router    Router mode (full-featured: NAT, firewall, PPPoE)
  ap        AP mode (mesh, minimal footprint)

Options:
  -c on|off      Enable/disable ccache (default: on)
  -j N           Number of parallel build jobs (default: $(nproc 2>/dev/null || nproc))
  -k PATH        Path to existing OpenWrt source tree (skip clone)
  -h             Show this help

Examples:
  $(basename "$0")                       # build router then ap
  $(basename "$0") router                 # build only router
  $(basename "$0") -j 2 ap               # build ap with 2 jobs
  $(basename "$0") -k ~/openwrt router    # reuse existing OpenWrt tree
EOF
    exit 0
}

while getopts "c:j:k:h" opt; do
    case "$opt" in
        c) USE_CCACHE="$OPTARG" ;;
        j) JOBS="$OPTARG" ;;
        k) OPENWRT_DIR="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -gt 0 ]; then
    VARIANTS="$*"
fi

# ── OS detection and dependency installation ──────────────────────────────
detect_os() {
    case "$(uname -s)" in
        Linux)
            if [ -f /etc/debian_version ] || [ -f /etc/ubuntu-release ]; then
                echo "debian"
            elif [ -f /etc/fedora-release ]; then
                echo "fedora"
            elif [ -f /etc/arch-release ]; then
                echo "arch"
            elif [ -f /etc/alpine-release ]; then
                echo "alpine"
            else
                echo "linux-unknown"
            fi
            ;;
        Darwin)
            echo "macos"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

install_deps_debian() {
    echo "=== Installing dependencies (Debian/Ubuntu) ==="
    sudo apt-get update
    sudo apt-get install -y \
        build-essential clang flex bison g++ gawk \
        gcc-multilib g++-multilib gettext git \
        libncurses-dev libssl-dev python3-distutils \
        python3-setuptools python3-dev rsync swig unzip \
        zlib1g-dev file wget curl jq device-tree-compiler \
        ccache libelf-dev libdw-dev libiberty-dev zstd
}

install_deps_fedora() {
    echo "=== Installing dependencies (Fedora) ==="
    sudo dnf install -y \
        gcc gcc-c++ clang flex bison gawk git \
        gettext ncurses-devel openssl-devel python3 \
        python3-pip python3-setuptools rsync swig unzip \
        zlib-devel file wget curl jq dtc ccache \
        elfutils-devel binutils zstd
}

install_deps_arch() {
    echo "=== Installing dependencies (Arch Linux) ==="
    sudo pacman -Sy --noconfirm --needed \
        gcc clang flex bison gawk git gettext \
        ncurses openssl python python-pip python-setuptools \
        rsync swig unzip zlib file wget curl jq dtc \
        ccache libelf zstd
}

install_deps_alpine() {
    echo "=== Installing dependencies (Alpine Linux) ==="
    sudo apk add \
        build-base clang flex bison g++ gawk git gettext \
        ncurses-dev openssl-dev python3 python3-dev py3-pip \
        rsync swig unzip zlib-dev file wget curl jq dtc \
        ccache libelf-dev zstd
}

install_deps_macos() {
    echo "=== Checking Homebrew dependencies (macOS) ==="
    if ! command -v brew &>/dev/null; then
        echo "ERROR: Homebrew is required. Install from https://brew.sh"
        exit 1
    fi
    brew install --quiet gcc llvm flex bison gawk gnu-sed \
        gettext ncurses openssl python3 rsync swig unzip \
        zlib file wget curl dtc ccache zstd jq 2>/dev/null || true
    echo "NOTE: Xcode Command Line Tools may also be needed:"
    echo "  xcode-select --install"
}

install_deps() {
    OS="$(detect_os)"
    case "$OS" in
        debian)       install_deps_debian ;;
        fedora)       install_deps_fedora ;;
        arch)         install_deps_arch ;;
        alpine)       install_deps_alpine ;;
        macos)        install_deps_macos ;;
        windows)
            echo "ERROR: Native Windows is not supported. Please use WSL2."
            exit 1
            ;;
        *)
            echo "WARNING: Unsupported OS '$(uname -s)'. Install dependencies manually."
            echo "See: https://openwrt.org/docs/guide-developer/build-system/install-buildsystem"
            return
            ;;
    esac
}

# ── Main build logic ─────────────────────────────────────────────────────

check_disk_space() {
    local avail_gb
    case "$(uname -s)" in
        Darwin) avail_gb="$(df -g / | awk 'NR==2{print $4}')" ;;
        *)      avail_gb="$(df -BG / | awk 'NR==2{print $4; exit}')" ;;
    esac
    avail_gb="${avail_gb%G*}"
    if [ "${avail_gb:-0}" -lt 25 ]; then
        echo "WARNING: Less than 25 GB free disk space (${avail_gb} GB available)."
        echo "         Build may fail. Consider freeing disk space."
    fi
}

show_info() {
    echo ""
    echo "=== Build Configuration ==="
    echo "  Variants:      $VARIANTS"
    echo "  Jobs:          $JOBS"
    echo "  ccache:        $USE_CCACHE"
    echo "  OpenWrt dir:   ${OPENWRT_DIR:-(will clone)}"
    echo "  Project root:  $PROJECT_ROOT"
    echo ""
    echo "=== System Info ==="
    echo "  OS:            $(uname -srm 2>/dev/null || uname -s)"
    echo "  Disk available:$(df -h / | awk 'NR==2{print " "$4}')"
    case "$(uname -s)" in
        Darwin) echo "  Memory:$(sysctl -n hw.memsize 2>/dev/null | awk '{printf " %.0f GB", $1/1024/1024/1024}')" ;;
        *)      echo "  Memory:$(free -h | awk '/^Mem:/{print " "$2} total, "$7" available}')" ;;
    esac
    echo ""
}

setup_ccache() {
    if [ "$USE_CCACHE" != "on" ]; then
        echo "=== ccache disabled ==="
        export CCACHE_DISABLE=1
        return
    fi
    echo "=== Configuring ccache ==="
    # In CI, align cache_dir with actions/cache path
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        ccache --set-config=cache_dir=~/.ccache
    fi
    ccache --set-config=max_size=10G
    ccache --set-config=compression=true
    ccache -z
}

prepare_openwrt() {
    if [ -n "$OPENWRT_DIR" ]; then
        if [ ! -d "$OPENWRT_DIR/.git" ]; then
            echo "ERROR: $OPENWRT_DIR is not a git repository"
            exit 1
        fi
        echo "=== Using existing OpenWrt tree: $OPENWRT_DIR ==="
        cd "$OPENWRT_DIR"
    else
        echo "=== Cloning OpenWrt ==="
        cd "$PROJECT_ROOT"
        # Preserve dl/ cache if it exists (restored by CI cache step)
        [ -d openwrt/dl ] && mv openwrt/dl /tmp/openwrt-dl-backup
        rm -rf openwrt
        git clone --depth 1 -b "$OPENWRT_BRANCH" "$OPENWRT_REPO" openwrt
        [ -d /tmp/openwrt-dl-backup ] && mv /tmp/openwrt-dl-backup openwrt/dl
        cd openwrt
        OPENWRT_DIR="$(pwd)"
    fi

    # Pin to a specific OpenWrt commit
    echo "=== Pinning OpenWrt to $OPENWRT_SHA ==="
    git fetch --depth=1 origin "$OPENWRT_SHA"
    git checkout "$OPENWRT_SHA"
}

merge_pr_and_fix_caldata() {
    echo ""
    echo "=== Applying PR #21495 (ath11k smallbuffers + PZ-L8 WiFi) ==="

    # Fetch the PR commit and its parent (needed for git diff and --3way merge)
    git fetch --depth=2 origin "$PR_21495_SHA" || {
        echo "ERROR: Failed to fetch PR commit $PR_21495_SHA"
        exit 1
    }

    # Extract and apply all PR changes (including caldata, which fix-caldata.sh
    # will then enhance with MAC/regdomain/macflag patches)
    if ! git diff FETCH_HEAD^..FETCH_HEAD | git apply --3way; then
        echo "WARNING: git apply encountered conflicts."
        # Find all .rej files
        REJ_FILES=$(git ls-files --others --exclude-standard "*.rej" 2>/dev/null)
        if [ -z "$REJ_FILES" ]; then
            REJ_FILES=$(find . -name "*.rej" -not -path "./.git/*" 2>/dev/null)
        fi
        if [ -z "$REJ_FILES" ]; then
            echo "No .rej files found, checking for other conflict indicators..."
            # git apply --3way may leave stage conflicts
            if git diff --quiet; then
                echo "No actual changes detected, continuing."
            else
                echo "ERROR: Conflict detected but no .rej files. Manual intervention needed."
                exit 1
            fi
        else
            NON_CALDATA_REJ=""
            for rej in $REJ_FILES; do
                case "$rej" in
                    *11-ath11k-caldata.rej)
                        echo "  Caldata conflict detected: $rej"
                        # Caldata conflict is expected: fix-caldata.sh will handle it
                        rm -f "$rej"
                        ;;
                    *)
                        NON_CALDATA_REJ="$NON_CALDATA_REJ $rej"
                        ;;
                esac
            done
            if [ -n "$NON_CALDATA_REJ" ]; then
                echo "ERROR: Non-caldata conflict(s):$NON_CALDATA_REJ"
                echo "Please check if OPENWRT_SHA or PR_21495_SHA needs updating."
                exit 1
            fi
        fi
        # Clean up any remaining .rej and .orig files
        find . \( -name "*.rej" -o -name "*.orig" \) -not -path "./.git/*" -delete 2>/dev/null || true
    fi

    echo "=== PR #21495 patches applied ==="

    # Enhance caldata entries added by PR with MAC/regdomain/macflag patches.
    CALDATA=target/linux/qualcommax/ipq50xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata
    echo "=== Applying fix-caldata.sh ==="
    chmod +x "$PROJECT_ROOT/scripts/fix-caldata.sh"
    "$PROJECT_ROOT/scripts/fix-caldata.sh" "$CALDATA"
}

apply_fm25ls01_patch() {
    echo ""
    echo "=== Adding FM25LS01 SPI NAND support (V2 hardware) ==="
    PATCH_DIR=target/linux/generic/backport-6.12
    PATCH_SRC="$PROJECT_ROOT/patches/add-fm25ls01-support.patch"
    PATCH_DST="$PATCH_DIR/440-v6.12-mtd-spinand-add-support-for-FudanMicro-FM25LS01.patch"

    if [ ! -f "$PATCH_SRC" ]; then
        echo "ERROR: FM25LS01 patch not found at $PATCH_SRC"
        exit 1
    fi

    cp "$PATCH_SRC" "$PATCH_DST"
    echo "=== FM25LS01 patch installed ==="
}

download_bdf_files() {
    echo ""
    echo "=== Downloading BDF files for PZ-L8 WiFi ==="
    mkdir -p files/lib/firmware/ath11k/IPQ5018/hw1.0
    mkdir -p files/lib/firmware/ath11k/QCN6122/hw1.0

    curl -L -o files/lib/firmware/ath11k/IPQ5018/hw1.0/board-2.bin \
        "https://github.com/openwrt/firmware_qca-wireless/raw/${BDF_COMMIT}/board-cmcc_pz-l8.ipq5018"
    curl -L -o files/lib/firmware/ath11k/QCN6122/hw1.0/board-2.bin \
        "https://github.com/openwrt/firmware_qca-wireless/raw/${BDF_COMMIT}/board-cmcc_pz-l8.qcn6122"

    echo "=== BDF files ==="
    ls -la files/lib/firmware/ath11k/IPQ5018/hw1.0/
    ls -la files/lib/firmware/ath11k/QCN6122/hw1.0/
}

update_feeds() {
    echo ""
    echo "=== Updating feeds ==="
    ./scripts/feeds update -a
    ./scripts/feeds install -a
}

download_toolchain() {
    echo ""
    echo "=== Trying precompiled toolchain ==="
    TOOLCHAIN_URL="https://downloads.openwrt.org/snapshots/targets/${TARGET}/${SUBTARGET}/"
    TOOLCHAIN_FILE=$(curl -sL "$TOOLCHAIN_URL" 2>/dev/null | grep -oP 'openwrt-toolchain[^"]+tar\.zst' | head -1)

    if [ -z "$TOOLCHAIN_FILE" ]; then
        echo "No precompiled toolchain found, will compile from source"
        return
    fi

    echo "Downloading $TOOLCHAIN_FILE ..."
    if curl -LO "${TOOLCHAIN_URL}${TOOLCHAIN_FILE}"; then
        echo "Extracting $TOOLCHAIN_FILE ..."
        # Extract to a temporary directory to avoid polluting the source tree
        TMPDIR_TOOLCHAIN="$(mktemp -d)"
        if zstd -d "$TOOLCHAIN_FILE" -o "$TMPDIR_TOOLCHAIN/toolchain.tar" && \
           tar -xf "$TMPDIR_TOOLCHAIN/toolchain.tar" -C "$TMPDIR_TOOLCHAIN"; then
            rm -f "$TOOLCHAIN_FILE" "$TMPDIR_TOOLCHAIN/toolchain.tar"
            # Find the toolchain directory: try both structures
            # Structure A: openwrt-toolchain-*/toolchain-* (OpenWrt toolchain tar)
            # Structure B: openwrt-toolchain-*/staging_dir/toolchain-*
            # Structure C: (flat, no wrapper) staging_dir/toolchain-*
            TOOLCHAIN_SRC=""
            WRAPPER=$(find "$TMPDIR_TOOLCHAIN" -maxdepth 1 -type d -name "openwrt-toolchain-*" | head -1)
            SEARCH_ROOT="${WRAPPER:-$TMPDIR_TOOLCHAIN}"
            TOOLCHAIN_SRC=$(find "$SEARCH_ROOT" -maxdepth 2 -type d -name "toolchain-aarch64_*" | head -1)
            if [ -z "$TOOLCHAIN_SRC" ]; then
                TOOLCHAIN_SRC=$(find "$SEARCH_ROOT" -maxdepth 3 -type d -path "*/staging_dir/toolchain-*" | head -1)
            fi
            if [ -n "$TOOLCHAIN_SRC" ]; then
                TOOLCHAIN_NAME=$(basename "$TOOLCHAIN_SRC")
                echo "=== Installing precompiled toolchain ($TOOLCHAIN_NAME) to staging_dir/ ==="
                cp -a "$TOOLCHAIN_SRC" staging_dir/
                echo "=== Precompiled toolchain installed ==="
            else
                echo "WARNING: No toolchain found in extracted archive, will compile from source"
                echo "Top-level contents:"
                ls "$SEARCH_ROOT/" | head -10
            fi
            rm -rf "$TMPDIR_TOOLCHAIN"
        else
            echo "Failed to extract toolchain, will compile from source"
            rm -f "$TOOLCHAIN_FILE" "$TMPDIR_TOOLCHAIN/toolchain.tar"
            rm -rf "$TMPDIR_TOOLCHAIN"
        fi
    else
        echo "Failed to download toolchain, will compile from source"
    fi
}

build_variants() {
    VARIANT_COUNT=$(echo "$VARIANTS" | wc -w)
    VARIANT_IDX=0
    BUILD_START=$(date +%s)

    for VARIANT in $VARIANTS; do
        VARIANT_IDX=$((VARIANT_IDX + 1))
        VARIANT_START=$(date +%s)
        echo ""
        echo "============================================================"
        echo "=== [$VARIANT_IDX/$VARIANT_COUNT] Building variant: $VARIANT ==="
        echo "=== Started: $(date -u +'%Y-%m-%dT%H:%M:%SZ') ==="
        echo "============================================================"

        VARIANT_DIR="$PROJECT_ROOT/variants/$VARIANT"
        ARTIFACT_DIR="$PROJECT_ROOT/artifacts/$VARIANT"
        mkdir -p "$ARTIFACT_DIR"

        # 1. Copy overlay files (clear previous variant's files first)
        rm -rf files/etc 2>/dev/null || true
        if [ -d "$VARIANT_DIR/etc" ]; then
            cp -r "$VARIANT_DIR/etc" files/
            echo "--- Copied overlay files ---"
            find files/etc -type f | sort
        fi

        # 2. Generate configuration
        if [ ! -f "$VARIANT_DIR/build.config" ]; then
            echo "ERROR: Config not found: $VARIANT_DIR/build.config"
            exit 1
        fi
        cp "$VARIANT_DIR/build.config" .config
        make defconfig
        make defconfig

        # 3. Download sources
        DL_START=$(date +%s)
        for i in 1 2 3; do
            echo "Download attempt $i/3..."
            if make download -j"$JOBS" V=s; then break; fi
            if [ $i -eq 3 ]; then
                echo "ERROR: Download failed after 3 attempts"
                exit 1
            fi
            sleep 30
        done
        DL_SEC=$(( $(date +%s) - DL_START ))
        echo "--- Download completed in ${DL_SEC}s ---"

        # 4. Build (skip toolchain/compile if precompiled toolchain is installed)
        BUILD_V_START=$(date +%s)
        PRECOMPILED_TC=$(find staging_dir -maxdepth 1 -type d -name 'toolchain-aarch64_*' 2>/dev/null | head -1)
        if [ -n "$PRECOMPILED_TC" ]; then
            echo "=== Using precompiled toolchain ($(basename "$PRECOMPILED_TC")), skipping toolchain/compile ==="
            # Build host tools (m4, bison, flex, etc.) required by kernel config
            make tools/compile -j"$JOBS" V=w
            make target/compile -j"$JOBS" V=w || make target/compile -j1 V=w || make target/compile -j1 V=s
            # Pre-create buildinfo stubs (base-files needs them, normally from make prepare)
            mkdir -p bin/targets/${TARGET}/${SUBTARGET}
            touch bin/targets/${TARGET}/${SUBTARGET}/{config,feeds,version}.buildinfo
            make package/compile -j"$JOBS" V=w || make package/compile -j1 V=w || make package/compile -j1 V=s
            make package/install -j"$JOBS" V=w
            make target/install -j"$JOBS" V=w
        else
            make -j"$JOBS" V=w || make -j1 V=w || make -j1 V=s
        fi
        BUILD_V_SEC=$(( $(date +%s) - BUILD_V_START ))
        echo "--- Build completed in ${BUILD_V_SEC}s ---"

        # 5. Collect artifacts
        cp -v bin/targets/${TARGET}/${SUBTARGET}/*factory*.ubi "$ARTIFACT_DIR/" 2>/dev/null || true
        cp -v bin/targets/${TARGET}/${SUBTARGET}/*sysupgrade*.bin "$ARTIFACT_DIR/" 2>/dev/null || true
        cp -v bin/targets/${TARGET}/${SUBTARGET}/*initramfs*.itb "$ARTIFACT_DIR/" 2>/dev/null || true
        echo "--- Artifacts for $VARIANT ---"
        ls -lh "$ARTIFACT_DIR/"

        VARIANT_SEC=$(( $(date +%s) - VARIANT_START ))
        echo ""
        echo "=== [$VARIANT_IDX/$VARIANT_COUNT] $VARIANT done in ${VARIANT_SEC}s ==="
    done

    TOTAL_SEC=$(( $(date +%s) - BUILD_START ))
    echo ""
    echo "=== All variants completed in ${TOTAL_SEC}s ==="
}

# ── Entry point ──────────────────────────────────────────────────────────
main() {
    show_info
    check_disk_space

    # Ask if we should install deps (skip if running in a CI environment)
    if [ -z "${CI:-}" ] && [ -z "${GITHUB_ACTIONS:-}" ]; then
        if ! command -v make &>/dev/null || ! command -v gcc &>/dev/null; then
            echo "Build dependencies not found. Install them now? [Y/n]"
            read -r answer
            case "$answer" in
                n*|N*) echo "Please install dependencies manually and re-run." && exit 1 ;;
                *)     install_deps ;;
            esac
        fi
    fi

    prepare_openwrt
    merge_pr_and_fix_caldata
    apply_fm25ls01_patch
    download_bdf_files
    setup_ccache
    update_feeds
    download_toolchain
    build_variants

    echo ""
    echo "=== ccache stats ==="
    if [ "$USE_CCACHE" = "on" ]; then
        ccache -s
    fi

    echo ""
    echo "=== Build complete ==="
    echo "Artifacts: $PROJECT_ROOT/artifacts/"
    find "$PROJECT_ROOT/artifacts" -type f 2>/dev/null | sort
}

main "$@"
