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

include scripts/make/variables.mk
include scripts/make/toolchain.mk
include scripts/make/signing.mk
include scripts/make/kconfig.mk

CMDLINE := $(project_name) console=tty0
TMPFILE := /tmp/$(project_name)
KERNEL_EXISTS := $(shell test -d $(KERNEL_DIR) && echo 1 || echo 0)
EXEC := TMPFILE=$(TMPFILE) RECOVERY=$(RECOVERY) VERBOSE=$(VERBOSE) PROJECT_DIR=$(PROJECT_DIR) $(SHELL)

ifeq ($(VERBOSE),1)
  CMDLINE := "$(CMDLINE) loglevel=9 console=ttyS0,115200"
endif

ifeq ($(TARGET),x86_64)
	CMDLINE := "kern_guid=%U $(CMDLINE)"
endif

.PHONY: usage arm64 x86_64 aarch64 config download-build-env build-inside-buildenv internal_buildenv cleanup-all cleanup-buildenv fullclean

usage:
	@echo "usage: make [x86_64|aarch64]"

# Arm64 is the same as Aarch64.
arm64: aarch64

x86_64: build-inside-buildenv
aarch64: build-inside-buildenv

$(WORK_DIR) $(OUTDIR) $(BUILDENV_DIR):
	$(Q)$(MKDIR) -p $@


# this is basically all we have to worry about in this file.
# maybe a better way to figure out if the build-env is downloaded
# or not?
download-build-env: $(BUILDENV_DIR)
ifeq ("$(wildcard $(BUILDENV_DIR)/.hello-world)","")
	@echo "  DOWNLOAD  build-env for $(HOST_ARCH)"
	$(Q)$(EXEC) scripts/download-build-env.sh $(BUILDENV_DIR) $(HOST_ARCH)
else
	@echo "  BUILDENV  (cached)"
endif

build-inside-buildenv: $(WORK_DIR) $(OUTDIR) download-build-env config gen-kconfig gen-config
	$(Q)$(SUDO) $(EXEC) scripts/build-in-buildenv.sh $(BUILDENV_DIR) $(PROJECT_DIR) $(TARGET)

include scripts/make/cleanup.mk
include scripts/make/buildenv.mk