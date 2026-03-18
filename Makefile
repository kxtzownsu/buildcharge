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

build-inside-buildenv: $(WORK_DIR) $(OUTDIR) download-build-env config
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
	@echo "  RM        $(BUILDENV_DIR)"
	@rm -rf $(BUILDENV_DIR)
	@echo "  RM        $(WORK_DIR)"
	@rm -rf $(WORK_DIR)
	@echo "  RM        $(OUTDIR)"
	@rm -rf $(OUTDIR)
	@echo "  RM        $(PROJECT_DIR)/scripts/lib/generated"
	@rm -rf $(PROJECT_DIR)/scripts/lib/generated
	@echo "  RM        .config"
	@rm -rf $(PROJECT_DIR)/.config
	@rm -rf $(PROJECT_DIR)/.config.old

# This target runs INSIDE the build-env chroot.
# We have this at the bottom of the Makefile so we can easily jump down to it.
internal_buildenv:
	$(Q)mkdir -p /packages
	$(Q)$(EXEC) $(PROJECT_DIR)/ramfs/scripts/parse-manifest.sh "$(PROJECT_DIR)/ramfs/manifest.json" "$(TOOLCHAIN)-" "$(ARCH)" /packages
	$(Q)$(EXEC) $(PROJECT_DIR)/ramfs/scripts/build-packages.sh "/tmp/manifest.json" "$(PROJECT_DIR)/.config" "/packages"