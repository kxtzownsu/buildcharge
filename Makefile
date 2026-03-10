project_name = buildcharge

TARGET :=
arm64: TARGET := arm64
x86_64: TARGET := x86_64
internal_buildenv: BUILDENV := 1 

include toolchain.mk

# We expect `VERBOSE=1`, nothing else.
ifeq ($(VERBOSE),1)
Q :=
else
Q := @
endif

WORK_DIR := $(abspath ./build/)
CONFDIR := $(abspath ./configs/)
OUTDIR := $(abspath ./out/)
BUILDENV_DIR := $(abspath $(WORK_DIR)/build-env/)
PROJECT_DIR := $(abspath .)
CMDLINE="$(project_name) console=tty0"
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
	$(Q)bash scripts/download-build-env.sh $(BUILDENV_DIR) $(HOST_ARCH) $(VERBOSE)
else
	@echo "  BUILDENV  (cached)"
endif

build-inside-buildenv: $(WORK_DIR) $(OUTDIR) download-build-env config
	$(Q)sudo bash scripts/build-in-buildenv.sh $(BUILDENV_DIR) $(PROJECT_DIR) $(TARGET) $(VERBOSE)

cleanup-buildenv:
	@echo "  UNMOUNT"
	$(Q)sudo bash scripts/cleanup-orphaned-mounts.sh $(PROJECT_DIR)

cleanup-all:
	@echo "  UNMOUNT"
	$(Q)sudo bash scripts/cleanup-orphaned-mounts.sh $(project_name)

# fullclean is dangerous if stuff is mounted & could result
# in a brick.
fullclean: cleanup-all
	@echo "  RM        $(BUILDENV_DIR)"
	@rm -rf $(BUILDENV_DIR)
	@echo "  RM        $(WORK_DIR)"
	@rm -rf $(WORK_DIR)
	@echo "  RM        $(OUTDIR)"
	@rm -rf $(OUTDIR)
	@echo "  RM        scripts/lib/generated"
	@rm -rf $(PROJECT_DIR)/scripts/lib/generated
	@echo "  RM        .config"
	@rm -rf $(PROJECT_DIR)/.config
	@rm -rf $(PROJECT_DIR)/.config.old

# This target runs INSIDE the build-env chroot.
# We have this at the bottom of the Makefile so we can easily jump down to it.
internal_buildenv:
	@echo "WIP"