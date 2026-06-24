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
    echo "::error::No variants found. Create variants/<name>/build.config files."
    exit 1
fi

PR_21495_SHA="bb1d6cf5472bf0a5e4ebe5f20bc03011122a5734"
BDF_COMMIT="f7ad5fee1924efdb5d8b2d1bf95bd3867d22e701"
OPENWRT_REPO="https://github.com/openwrt/openwrt.git"
OPENWRT_BRANCH="main"
OPENWRT_SHA="a5c5ca0666533a0af027e73f80fbc94f21be54c3"

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
        echo "::error::Homebrew is required. Install from https://brew.sh"
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
            echo "::error::Native Windows is not supported. Please use WSL2."
            exit 1
            ;;
        *)
            echo "::warning::Unsupported OS '$(uname -s)'. Install dependencies manually."
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
        echo "::warning::Less than 25 GB free disk space (${avail_gb} GB available)."
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
        *)      echo "  Memory:$(free -h | awk '/^Mem:/{print " "$2" total, "$7" available}')" ;;
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
    # Configure the system ccache (used by build.sh for stats).
    # OpenWrt's own ccache (staging_dir/host/bin/ccache) reads the same
    # config file (~/.config/ccache/ccache.conf), so max_size and compression
    # settings apply to both. The cache_dir setting here only affects system
    # ccache; OpenWrt overrides it via CCACHE_DIR env var (set in rules.mk:354
    # to $(TOPDIR)/.ccache = openwrt/.ccache), which is what actions/cache
    # caches (see .github/workflows/build.yml "Cache ccache" step).
    ccache --set-config=max_size=10G
    ccache --set-config=compression=true
    ccache -z

    # Show effective CCACHE_DIR for debugging
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        echo "CI: ccache cache_dir will be openwrt/.ccache (set by OpenWrt rules.mk)"
        echo "CI: actions/cache caches openwrt/.ccache path"
    fi
}

prepare_openwrt() {
    if [ -n "$OPENWRT_DIR" ]; then
        if [ ! -d "$OPENWRT_DIR/.git" ]; then
            echo "::error::$OPENWRT_DIR is not a git repository"
            exit 1
        fi
        echo "=== Using existing OpenWrt tree: $OPENWRT_DIR ==="
        cd "$OPENWRT_DIR"
    else
        echo "=== Cloning OpenWrt ==="
        cd "$PROJECT_ROOT"
        # Preserve caches across openwrt clone. prepare_openwrt does 'rm -rf
        # openwrt' below, which would delete these caches. We back them up to
        # /tmp and restore after clone.
        # - openwrt/dl: source tarballs (actions/cache "Cache dl")
        # - openwrt/.ccache: compiler cache (actions/cache "Cache ccache",
        #   CCACHE_DIR is set to $(TOPDIR)/.ccache by OpenWrt rules.mk:354)
        # - openwrt/staging_dir/host + openwrt/build_dir/host: host tools
        #   binaries, source, and stamp files (actions/cache "Cache host tools").
        #   Both are needed together: _installed stamp (in staging_dir) depends
        #   on _built stamp (in build_dir). Without build_dir stamps, make
        #   re-runs prepare→configure→compile→install from scratch.
        [ -d openwrt/dl ] && mv openwrt/dl /tmp/openwrt-dl-backup
        [ -d openwrt/.ccache ] && mv openwrt/.ccache /tmp/openwrt-ccache-backup
        [ -d openwrt/staging_dir/host ] && mv openwrt/staging_dir/host /tmp/openwrt-staging-host-backup
        [ -d openwrt/build_dir/host ] && mv openwrt/build_dir/host /tmp/openwrt-build-host-backup
        rm -rf openwrt
        # Full clone (no --depth) so merge-base works for three-dot PR diff
        git clone -b "$OPENWRT_BRANCH" "$OPENWRT_REPO" openwrt
        [ -d /tmp/openwrt-dl-backup ] && mv /tmp/openwrt-dl-backup openwrt/dl
        [ -d /tmp/openwrt-ccache-backup ] && mv /tmp/openwrt-ccache-backup openwrt/.ccache
        [ -d /tmp/openwrt-staging-host-backup ] && mkdir -p openwrt/staging_dir && mv /tmp/openwrt-staging-host-backup openwrt/staging_dir/host
        [ -d /tmp/openwrt-build-host-backup ] && mkdir -p openwrt/build_dir && mv /tmp/openwrt-build-host-backup openwrt/build_dir/host
        cd openwrt
        OPENWRT_DIR="$(pwd)"
    fi

    # Pin to a specific OpenWrt commit
    echo "=== Pinning OpenWrt to $OPENWRT_SHA ==="
    git fetch origin "$OPENWRT_SHA"
    git checkout "$OPENWRT_SHA"

    # Normalize mtime of tools/ directory to make find_md5 hash deterministic.
    # OpenWrt's host-build.mk uses find_md5 (which includes file mtime via
    # printf '%T@') to compute .prepared stamp filenames. After git clone +
    # checkout, all files have current mtime → hash differs from cached
    # build_dir/host stamps → stamps not recognized → tools recompiled from
    # scratch (~17 min wasted).
    # Setting mtime to a fixed date makes the hash deterministic across builds,
    # so cached stamps are recognized and tools/compile is skipped.
    # Only touch tools/ (not the entire tree) to avoid side effects on other
    # build components.
    find tools -type f -exec touch -d '2020-01-01 00:00:00' {} +
}

merge_pr_21495() {
    echo ""
    echo "=== Applying PR #21495 (ath11k smallbuffers + PZ-L8 WiFi) ==="

    # Fetch the PR commit (full history available since prepare_openwrt does full clone)
    git fetch origin "$PR_21495_SHA" || {
        echo "::error::Failed to fetch PR commit $PR_21495_SHA"
        exit 1
    }

    # Use three-dot diff to extract only PR #21495's own changes.
    # git diff origin/main...PR_21495_SHA = diff from merge-base to PR_21495_SHA,
    # which excludes unrelated OpenWrt changes between OPENWRT_SHA and PR's base.
    #
    # Exclude the ath11k caldata hotplug script from PR apply. PR #21495 adds
    # cmcc,pz-l8 entries to it but in a "bare" form (caldata_extract only,
    # no MAC patch). We apply our own caldata patch (patches/openwrt/001-pz-l8-caldata.patch)
    # afterwards which inserts cmcc,pz-l8 case blocks with full MAC patch.
    # This decouples our caldata handling from PR's writing style.
    if ! git diff "origin/$OPENWRT_BRANCH"..."$PR_21495_SHA" \
            | git apply --3way \
                --exclude='target/linux/qualcommax/ipq50xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata'; then
        echo "::warning::git apply encountered conflicts."
        # Find all .rej files
        REJ_FILES=$(git ls-files --others --exclude-standard "*.rej" 2>/dev/null)
        if [ -z "$REJ_FILES" ]; then
            REJ_FILES=$(find . -name "*.rej" -not -path "./.git/*" 2>/dev/null)
        fi
        if [ -n "$REJ_FILES" ]; then
            echo "::error::PR apply conflicts detected:$REJ_FILES"
            echo "Please check if OPENWRT_SHA or PR_21495_SHA needs updating."
            exit 1
        fi
        # No .rej files - check if there are actual changes
        if ! git diff --quiet; then
            echo "::error::Conflict detected but no .rej files. Manual intervention needed."
            exit 1
        fi
        echo "No actual changes detected, continuing."
    fi

    echo "=== PR #21495 patches applied ==="
}

apply_openwrt_patches() {
    echo ""
    echo "=== Applying OpenWrt patches ==="
    # Patches in patches/openwrt/ modify base-files, hotplug scripts, or other
    # non-kernel files in the OpenWrt tree. Applied via 'git apply'.
    # Adding a new openwrt patch: just drop a .patch file in patches/openwrt/,
    # no build.sh changes needed.
    for patch in "$PROJECT_ROOT"/patches/openwrt/*.patch; do
        [ -f "$patch" ] || continue
        echo "--- Applying $(basename "$patch") ---"
        if ! git apply "$patch"; then
            echo "::error::Patch $(basename "$patch") failed to apply."
            echo "This usually means OpenWrt main's file structure changed."
            echo "Regenerate $patch against the new file:"
            echo "  1. Edit the target file in OpenWrt tree"
            echo "  2. git diff -- <file> > $patch"
            exit 1
        fi
    done

    # Sanity check: verify cmcc,pz-l8 has the MAC patch (not just caldata_extract)
    CALDATA=target/linux/qualcommax/ipq50xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata
    if [ "$(grep -c 'ath11k_patch_mac.*label_mac' "$CALDATA")" -lt 2 ]; then
        echo "::error::Caldata patch applied but MAC patch missing or incomplete."
        echo "Expected 2 ath11k_patch_mac calls (2.4GHz + 5GHz), found $(grep -c 'ath11k_patch_mac.*label_mac' "$CALDATA")."
        exit 1
    fi
    echo "=== OpenWrt patches applied ==="
}

apply_kernel_patches() {
    echo ""
    echo "=== Installing kernel patches ==="
    # Patches in patches/kernel/ are copied to OpenWrt's kernel patch directory,
    # where OpenWrt's quilt system applies them during kernel preparation.
    # These patches modify kernel source code and affect compilation.
    # Adding a new kernel patch: just drop a .patch file in patches/kernel/,
    # no build.sh changes needed.
    PATCH_DIR=target/linux/generic/backport-6.12
    mkdir -p "$PATCH_DIR"
    for patch in "$PROJECT_ROOT"/patches/kernel/*.patch; do
        [ -f "$patch" ] || continue
        echo "--- Installing $(basename "$patch") ---"
        cp "$patch" "$PATCH_DIR/$(basename "$patch")"
    done
    echo "=== Kernel patches installed ==="
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
    # Use HTTP/1.1 to avoid HTTP/2 PROTOCOL_ERROR on flaky runner networks.
    # Retry up to 5 times with 5s delay to ride out transient failures
    # (downloads.openwrt.org occasionally drops connections mid-stream).
    if curl -LO --http1.1 --retry 5 --retry-delay 5 --retry-connrefused \
            "${TOOLCHAIN_URL}${TOOLCHAIN_FILE}"; then
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
                echo "::warning::No toolchain found in extracted archive, will compile from source"
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
            echo "::error file=$VARIANT_DIR/build.config::Config file not found"
            exit 1
        fi
        cp "$VARIANT_DIR/build.config" .config

        # Strict config validation via kconfig's native strict mode.
        # - KCONFIG_WARN_UNKNOWN_SYMBOLS=1: warn on any CONFIG_X in .config that
        #   kconfig doesn't recognize (typos, removed packages, wrong target, etc.)
        # - KCONFIG_WERROR=1: treat those warnings as errors (non-zero exit)
        # This replaces the previous BEFORE/AFTER diff linter which only covered
        # CONFIG_PACKAGE_*=y and missed CONFIG_TARGET_*, CONFIG_KERNEL_*, =m,
        # value changes, and multi-target conflicts. Kconfig's own symbol table
        # is the authoritative source of truth.
        # Note: must run AFTER prepare_openwrt + merge_pr_21495 +
        # update_feeds, otherwise patch-introduced symbols would false-positive.
        #
        # IMPORTANT: pass these env vars ONLY to the defconfig invocation,
        # do NOT export them globally. Otherwise they leak into target/compile
        # (kernel build's syncconfig), which then fails because OpenWrt's
        # defconfig-generated .config contains 'not set' lines for symbols
        # from other architectures (ARM/X86/PPC) that the aarch64 kernel
        # symbol table doesn't recognize - 945 false positives, all fatal
        # under KCONFIG_WERROR.
        DEFCONFIG_LOG="/tmp/defconfig-$VARIANT.log"
        if ! env KCONFIG_WARN_UNKNOWN_SYMBOLS=1 KCONFIG_WERROR=1 \
                make defconfig 2>&1 | tee "$DEFCONFIG_LOG"; then
            echo ""
            echo "::error file=$VARIANT_DIR/build.config::Config validation failed (see kconfig warnings above)"
            echo "Common causes:"
            echo "  - Typo in CONFIG_X name (check spelling against OpenWrt Config.in)"
            echo "  - Package removed/renamed in current OpenWrt/feeds version"
            echo "  - Wrong target/device for this branch"
            echo "  - Invalid value (must be y/m/n/\"string\"/number; first char matters)"
            echo ""
            echo "Annotated errors (also visible on PR Files changed page):"
            # Convert kconfig warnings/errors to GitHub Actions ::error annotations
            # so they show up inline on the PR diff view.
            # Format 1: .config:NN:warning: <message>
            # Format 2: .config:NN: *** <message>  (kconfig parser hard error)
            # The line number in .config matches build.config (we cp'd it).
            CI_FILE="$VARIANT_DIR/build.config"
            while IFS= read -r line; do
                # Match kconfig warning format: .config:NN:warning: <msg>
                if [[ "$line" =~ ^\.config:([0-9]+):warning:\ (.+)$ ]]; then
                    echo "::error file=$CI_FILE,line=${BASH_REMATCH[1]}::${BASH_REMATCH[2]}"
                # Match kconfig parser error format: .config:NN: *** <msg>
                elif [[ "$line" =~ ^\.config:([0-9]+):\ \*\*\*\ (.+)$ ]]; then
                    echo "::error file=$CI_FILE,line=${BASH_REMATCH[1]}::${BASH_REMATCH[2]}"
                fi
            done < "$DEFCONFIG_LOG"
            exit 1
        fi

        # Run defconfig a second time to ensure dependency convergence.
        # If the second run changes .config, that indicates unstable config
        # (dependency cycle or incomplete resolution) - treat as error.
        cp .config /tmp/.config-first-pass
        env KCONFIG_WARN_UNKNOWN_SYMBOLS=1 KCONFIG_WERROR=1 \
            make defconfig 2>&1 | tee "$DEFCONFIG_LOG"
        if ! diff -q /tmp/.config-first-pass .config >/dev/null; then
            echo "::error file=$VARIANT_DIR/build.config::defconfig did not converge (2nd run changed .config)"
            echo "This indicates unstable config - check for dependency conflicts."
            diff /tmp/.config-first-pass .config | head -30
            exit 1
        fi

        # 3. Download sources
        DL_START=$(date +%s)
        for i in 1 2 3; do
            echo "Download attempt $i/3..."
            if make download -j"$JOBS" V=s; then break; fi
            if [ $i -eq 3 ]; then
                echo "::error::Download failed after 3 attempts"
                exit 1
            fi
            sleep 30
        done
        DL_SEC=$(( $(date +%s) - DL_START ))
        echo "--- Download completed in ${DL_SEC}s ---"

        # 4. Build (skip toolchain/compile if precompiled toolchain is installed)
        BUILD_V_START=$(date +%s)
        # Detect precompiled toolchain by checking for the actual gcc binary, not
        # just the directory existence. OpenWrt's make system pre-creates
        # staging_dir/toolchain-* as an empty stub during prereq, which would
        # falsely pass a directory-only check and cause toolchain/compile to be
        # skipped, leading to 'ccache: error: Could not find compiler' later.
        PRECOMPILED_TC=""
        for tc_dir in staging_dir/toolchain-aarch64_*; do
            [ -d "$tc_dir" ] || continue
            if [ -x "$tc_dir/bin/aarch64-openwrt-linux-musl-gcc" ]; then
                PRECOMPILED_TC="$tc_dir"
                break
            fi
        done
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
    merge_pr_21495
    apply_openwrt_patches
    apply_kernel_patches
    download_bdf_files
    setup_ccache
    update_feeds
    download_toolchain
    build_variants

    echo ""
    echo "=== ccache stats ==="
    if [ "$USE_CCACHE" = "on" ]; then
        # Use OpenWrt's ccache binary with the correct CCACHE_DIR.
        # System ccache (used by build.sh setup) has a different cache_dir
        # and would show 0/0 stats. OpenWrt sets CCACHE_DIR=$(TOPDIR)/.ccache
        # during build, so we need to replicate that here.
        OPENWRT_CCACHE="$OPENWRT_DIR/staging_dir/host/bin/ccache"
        if [ -x "$OPENWRT_CCACHE" ]; then
            CCACHE_DIR="$OPENWRT_DIR/.ccache" "$OPENWRT_CCACHE" -s
        else
            echo "(OpenWrt ccache binary not found at $OPENWRT_CCACHE)"
            echo "This usually means tools/ccache/compile was skipped."
            ccache -s
        fi
    fi

    echo ""
    echo "=== Build complete ==="
    echo "Artifacts: $PROJECT_ROOT/artifacts/"
    find "$PROJECT_ROOT/artifacts" -type f 2>/dev/null | sort
}

main "$@"
