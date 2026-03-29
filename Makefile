project_name = buildcharge
USE_DEFAULT_CONFIG := 1
KERNEL_REPO := https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_BRANCH := v6.12.48

TARGET :=
# ramfs relies on target as aarch64, not arm64, even though they're the same.
aarch64: TARGET := aarch64
x86_64: TARGET := x86_64
clean-aarch64: TARGET := aarch64
clean-x86_64: TARGET := x86_64
internal_buildenv: BUILDENV := 1 

ifeq ($(TARGET),aarch64)
  KERNEL_TARGET := arm64
else ifeq ($(TARGET),x86_64)
  KERNEL_TARGET := x86
endif

include toolchain.mk
include signing.mk

PROJECT_DIR := $(abspath .)
WORK_DIR := $(abspath $(PROJECT_DIR)/build/)
CONFDIR := $(abspath $(PROJECT_DIR)/configs/)
OUTDIR := $(abspath $(PROJECT_DIR)/out/)
BUILDENV_DIR := $(abspath $(WORK_DIR)/build-env/)
CMDLINE := $(project_name) console=tty0
TMPFILE := /tmp/$(project_name)
KERNEL_BUILD_DIR := $(WORK_DIR)/kernel/$(TARGET)/
include kconfig.mk

ifeq ($(BUILDENV),1)
INITFS_DIR := /initfs/$(TARGET)/
PACKAGE_DIR := /packages/$(TARGET)/
KERNEL_DIR := /kernel/
endif
ifneq ($(BUILDENV),1)
INITFS_DIR := $(WORK_DIR)/initfs/$(TARGET)/
PACKAGE_DIR := $(WORK_DIR)/packages/$(TARGET)/
KERNEL_DIR := $(WORK_DIR)/kernel/
endif

KERNEL_EXISTS := $(shell test -d $(KERNEL_DIR) && echo 1 || echo 0)

INITFS_CPIO := $(WORK_DIR)/ramfs/$(project_name).$(TARGET).cpio
INITFS_CPIOZ := $(INITFS_CPIO).xz
KPART := $(WORK_DIR)/$(project_name).$(TARGET).kpart
IMG := $(WORK_DIR)/$(project_name).$(TARGET).bin
BZIMAGE := $(WORK_DIR)/kernel/$(project_name).$(TARGET).bzImage

ifeq ($(VERBOSE),1)
  CMDLINE := "$(CMDLINE) loglevel=9 console=ttyS0,115200"
endif

ifeq ($(TARGET),x86_64)
	CMDLINE := "kern_guid=%U $(CMDLINE)"
endif

EXEC := TMPFILE=$(TMPFILE) RECOVERY=$(RECOVERY) VERBOSE=$(VERBOSE) PROJECT_DIR=$(PROJECT_DIR) $(SHELL)

.PHONY: usage arm64 x86_64 aarch64 config download-build-env build-inside-buildenv internal_buildenv cleanup-all cleanup-buildenv fullclean

usage:
	@echo "usage: make [x86_64|aarch64]"

# Arm64 is the same as Aarch64.
arm64: aarch64

x86_64: build-inside-buildenv
aarch64: build-inside-buildenv

$(WORK_DIR):
	$(Q)$(MKDIR) -p $(WORK_DIR)

$(OUTDIR):
	$(Q)$(MKDIR) -p $(OUTDIR)

$(BUILDENV_DIR):
	$(Q)$(MKDIR) -p $(BUILDENV_DIR)

download-build-env: $(BUILDENV_DIR)
ifeq ("$(wildcard $(BUILDENV_DIR)/.hello-world)","")
	@echo "  DOWNLOAD  build-env for $(HOST_ARCH)"
	$(Q)$(EXEC) scripts/download-build-env.sh $(BUILDENV_DIR) $(HOST_ARCH)
else
	@echo "  BUILDENV  (cached)"
endif

build-inside-buildenv: $(WORK_DIR) $(OUTDIR) download-build-env config gen-kconfig gen-config
	$(Q)$(SUDO) $(EXEC) scripts/build-in-buildenv.sh $(BUILDENV_DIR) $(PROJECT_DIR) $(TARGET)

cleanup-buildenv:
	@echo "  UNMOUNT"
	$(Q)$(SUDO) $(EXEC) scripts/cleanup-orphaned-mounts.sh $(PROJECT_DIR)

cleanup-all:
	@echo "  UNMOUNT"
	$(Q)$(SUDO) $(EXEC) scripts/cleanup-orphaned-mounts.sh $(project_name)

clean:
	@echo "The typical 'make clean' does not work with buildcharge."
	@echo "You must use 'make clean-[arch], for example: make clean-x86_64 or make clean-aarch64"

clean-arm64: clean-aarch64

clean-x86_64 clean-aarch64:
	$(Q)$(MAKE) TARGET=$(TARGET) internal_clean

internal_clean:
	@echo "  SUDORM    $(BZIMAGE)"
	$(Q)$(SUDO) $(RM) -rf $(BZIMAGE)
	@echo "  SUDORM    $(INITFS_CPIO)"
	$(Q)$(SUDO) $(RM) -rf $(INITFS_CPIO)
	@echo "  SUDORM    $(INITFS_CPIOZ)"
	$(Q)$(SUDO) $(RM) -rf $(INITFS_CPIOZ)
	@echo "  SUDORM    $(KPART)"
	$(Q)$(SUDO) $(RM) -rf $(KPART)
	@echo "  SUDORM    $(INITFS_DIR)"
	$(Q)$(SUDO) $(RM) -rf $(INITFS_DIR)

# fullclean is dangerous if stuff is mounted & could result
# in a brick.
fullclean: cleanup-all
	@echo "  SUDORM    $(BUILDENV_DIR)"
	@$(SUDO) $(RM) -rf $(BUILDENV_DIR)
	@echo "  SUDORM    $(WORK_DIR)"
	@$(SUDO) $(RM) -rf $(WORK_DIR)
	@echo "  SUDORM    $(OUTDIR)"
	@$(SUDO) $(RM) -rf $(OUTDIR)
	@echo "  RM        $(PROJECT_DIR)/scripts/lib/generated"
	@$(RM) -rf $(PROJECT_DIR)/scripts/lib/generated
	@echo "  RM        .config"
	@$(RM) -rf $(PROJECT_DIR)/.config
	@$(RM) -rf $(PROJECT_DIR)/.config.old

# Any targets below this line run INSIDE the build-env.
# We have this at the bottom of the Makefile so we can easily jump down to it.
# P.S: we're running as root so we don't need $(SUDO)

$(BZIMAGE):
ifneq ($(KERNEL_EXISTS),1)
	@echo "  GIT       kernel"
	$(Q)$(GIT) clone $(KERNEL_REPO) --depth 1 -b $(KERNEL_BRANCH) $(KERNEL_DIR)
else
	@echo "  GIT       kernel (exists)"
endif
	$(Q)apk add elfutils-dev bc ncurses-dev mpfr-dev gmp-dev mpc1-dev
	$(Q)$(FIND) $(PROJECT_DIR)/patches/kernel/ -type f -print0 | xargs -0 -n 1 patch -fud $(KERNEL_DIR) -p1
	$(Q)$(MKDIR) -p $(KERNEL_BUILD_DIR)
# 	$(Q)CROSS_COMPILE=$(CROSS_COMPILE) ARCH=$(KERNEL_TARGET) $(MAKE) -C $(KERNEL_DIR) O=$(KERNEL_BUILD_DIR) mrproper
	$(Q)$(COPY) $(PROJECT_DIR)/configs/kernel/config.$(TARGET) $(KERNEL_BUILD_DIR)/.config
# 	$(Q)$(COPY) $(PROJECT_DIR)/configs/kernel/config.$(TARGET) $(KERNEL_DIR)/.config
	$(Q)CROSS_COMPILE=$(CROSS_COMPILE) ARCH=$(KERNEL_TARGET) $(MAKE) -C $(KERNEL_DIR) O=$(KERNEL_BUILD_DIR) olddefconfig
	$(Q)CROSS_COMPILE=$(CROSS_COMPILE) ARCH=$(KERNEL_TARGET) $(MAKE) -C $(KERNEL_DIR) O=$(KERNEL_BUILD_DIR)
ifeq ($(TARGET),aarch64)
	$(Q)CROSS_COMPILE=$(CROSS_COMPILE) ARCH=$(KERNEL_TARGET) $(MAKE) -C $(KERNEL_DIR) O=$(KERNEL_BUILD_DIR) dtbs_install INSTALL_DTBS_PATH=$(WORK_DIR)/dtbs/
	$(Q)$(COPY) $(KERNEL_BUILD_DIR)/arch/$(KERNEL_TARGET)/boot/Image.gz $(BZIMAGE)
endif
ifeq ($(TARGET),x86_64)
	$(Q)$(COPY) $(KERNEL_BUILD_DIR)/arch/$(KERNEL_TARGET)/boot/bzImage $(BZIMAGE)
endif

$(INITFS_CPIO):
	$(Q)$(MKDIR) -p "$(PACKAGE_DIR)"
	$(Q)$(MKDIR) -p "$(PROJECT_DIR)/build/ramfs/" "$(PROJECT_DIR)/build/kernel/"
	$(Q)$(EXEC) $(PROJECT_DIR)/ramfs/scripts/parse-manifest.sh "$(PROJECT_DIR)/ramfs/manifest.json" "$(TOOLCHAIN)-" "$(ARCH)" "$(PACKAGE_DIR)"
	$(Q)$(EXEC) $(PROJECT_DIR)/ramfs/scripts/build-packages.sh "/tmp/manifest.json" "$(PACKAGE_DIR)"
	$(Q)$(CHOWN) -R root:root $(INITFS_DIR)
	$(Q)$(CHMOD) -R +x $(INITFS_DIR)/bin/
	$(Q)$(CHMOD) -R +x $(INITFS_DIR)/sbin/
	$(Q)cd $(INITFS_DIR) && find . -print | cpio -o -H newc -F $(INITFS_CPIO)

$(INITFS_CPIOZ): $(INITFS_CPIO)
	$(Q)$(XZ) -kf -9 --check=crc32 $(INITFS_CPIO)
	
$(KPART): $(BZIMAGE)
	$(Q)echo "  KPART      $(KPART)"
	$(Q)echo $(CMDLINE) >> $(TMPFILE)
ifeq ($(TARGET),x86_64)
	$(Q)apk add vboot-utils
	$(Q)$(FUTILITY) vbutil_kernel --pack $(KPART) --signprivate $(DATA_KEY) --keyblock $(KEYBLOCK) --config $(TMPFILE) --bootloader $(TMPFILE) --vmlinuz $(BZIMAGE) --version 1 --arch $(KERNEL_TARGET)
endif
ifeq ($(TARGET),aarch64)
ifeq ($(RECOVERY),1)
	$(Q)echo "|-!-| Building aarch64 images with recovery keys does not work due to a depthchargectl bug. Please resign using make_dev_ssd.sh and --recovery_key |-!-|"
endif
	$(Q)apk add depthcharge-tools
	$(Q)$(DEPTHCHARGECTL) build \
			--board arm64-generic \
			--kernel $(BZIMAGE) \
			--fdtdir $(WORK_DIR)/dtbs \
			--root none \
			--kernel-cmdline $(CMDLINE) \
			--vboot-keyblock $(KEYBLOCK) \
			--vboot-private-key $(DATA_KEY) \
			--output $(KPART)
endif
	$(Q)$(MKDIR) -p $(OUTDIR)
	$(Q)$(COPY) $(KPART) $(OUTDIR)

internal_buildenv: $(INITFS_CPIOZ) $(BZIMAGE) $(KPART)