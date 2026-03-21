project_name = buildcharge
USE_DEFAULT_CONFIG := 1

TARGET :=
arm64: TARGET := arm64
x86_64: TARGET := x86_64
internal_buildenv: BUILDENV := 1 

include toolchain.mk

WORK_DIR := $(abspath ./build/)
CONFDIR := $(abspath ./configs/)
OUTDIR := $(abspath ./out/)
BUILDENV_DIR := $(abspath $(WORK_DIR)/build-env/)
PROJECT_DIR := $(abspath .)
CMDLINE="$(project_name) console=tty0"
EXEC := VERBOSE=$(VERBOSE) PROJECT_DIR=$(PROJECT_DIR) $(SHELL)
include kconfig.mk

INITFS_DIR := /initfs
PACKAGE_DIR := /packages

INITFS_CPIO := $(project_name).$(TARGET).cpio
INITFS_CPIOZ := $(INITFS_CPIO).xz
KPART := $(project_name).$(TARGET).kpart
IMG := $(project_name).$(TARGET).bin
BZIMAGE := $(project_name).$(TARGET).bzImage

ifeq ($(VERBOSE),1)
	CMDLINE="$(CMDLINE) loglevel=9 console=ttyS0,115200"
endif

.PHONY: usage arm64 x86_64 aarch64 config download-build-env build-inside-buildenv internal_buildenv cleanup-all cleanup-buildenv fullclean

usage:
	@echo "usage: make [x86_64|arm64]"
	@echo "(aarch64 == arm64)"

# Aarch64 is the same as Arm64.
aarch64: arm64

# We don't have to do anything architecture-specific, 
# toolchain.mk should handle this.
x86_64: build-inside-buildenv
arm64: build-inside-buildenv

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

# This target runs INSIDE the build-env chroot.
# We have this at the bottom of the Makefile so we can easily jump down to it.
# P.S: we're running as root so we don't need $(SUDO)
internal_buildenv:
	$(Q)$(MKDIR) -p "$(PACKAGE_DIR)"
	$(Q)$(MKDIR) -p "$(PROJECT_DIR)/build/ramfs/" "$(PROJECT_DIR)/build/kernel/"
	$(Q)$(EXEC) $(PROJECT_DIR)/ramfs/scripts/parse-manifest.sh "$(PROJECT_DIR)/ramfs/manifest.json" "$(TOOLCHAIN)-" "$(ARCH)" "$(PACKAGE_DIR)"
	$(Q)$(EXEC) $(PROJECT_DIR)/ramfs/scripts/build-packages.sh "/tmp/manifest.json" "$(PACKAGE_DIR)"
	$(Q)$(CHOWN) -R root:root $(INITFS_DIR)
	$(Q)$(CHMOD) -R +x $(INITFS_DIR)/bin/
	$(Q)$(CHMOD) -R +x $(INITFS_DIR)/sbin/
	$(Q)cd $(INITFS_DIR) && find . -print | cpio -o -H newc -F $(INITFS_CPIO)
	$(Q)$(MOVE) $(INITFS_DIR)/$(INITFS_CPIO) $(PROJECT_DIR)/build/ramfs/
	$(Q)$(XZ) -kf -9 --check=crc32 $(PROJECT_DIR)/build/ramfs/$(INITFS_CPIO)