project_name := buildcharge # this is just the default to prevent errors.
USE_DEFAULT_CONFIG := 1
KERNEL_REPO := https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
KERNEL_BRANCH := v6.12.48
KERNEL_VERSION := 1

internal_buildenv: BUILDENV := 1 

# ramfs relies on target as aarch64, not arm64, even though they're the same.
TARGET :=

ifneq ($(filter x86_64 clean-x86_64,$(MAKECMDGOALS)),)
TARGET := x86_64
endif
ifneq ($(filter aarch64 arm64 clean-aarch64 clean-arm64,$(MAKECMDGOALS)),)
TARGET := aarch64
endif

# github action-specific things
ifeq ($(ACTION),1)
SILENT := 1
endif

ifeq ($(TARGET),aarch64)
  KERNEL_TARGET := arm64
else ifeq ($(TARGET),x86_64)
  KERNEL_TARGET := x86
endif

include scripts/make/variables.mk
include scripts/make/kconfig.mk

ifeq ($(wildcard $(DOT_CONFIG)),)
# this is the same logic thats in the 'config' target,
# keep them as identical as possible
ifneq ($(PROJECT),)
# we have to hardcode the copy command here since we haven't
# included 'toolchain.mk' yet
$(shell cp $(PROJECT_DIR)/configs/projects/$(PROJECT)/default.$(TARGET) $(DOT_CONFIG))
else ifeq ($(USE_DEFAULT_CONFIG),1)
$(shell cp $(PROJECT_DIR)/configs/projects/buildcharge/default.$(TARGET) $(DOT_CONFIG))
else
$(shell $(KCONFIG_SCRIPT) check $(KCONFIG_FLAGS))
endif
endif

_project_name_from_config := $(shell $(KCONFIG_SCRIPT) get-dotconfig-val --dot-config $(DOT_CONFIG) --config-key CONFIG_PROJECT_NAME | tr -d '"')
ifeq ($(_project_name_from_config),)
  $(error CONFIG_PROJECT_NAME is empty or missing in $(DOT_CONFIG))
endif
ifneq ($(words $(_project_name_from_config)),1)
  $(error invalid CONFIG_PROJECT_NAME '$(_project_name_from_config)' from $(DOT_CONFIG))
endif
project_name := $(_project_name_from_config)

include scripts/make/variables.mk # re-include now that we have the proper project_name
include scripts/make/toolchain.mk
include scripts/make/signing.mk

CMDLINE := $(project_name) console=tty0
TMPFILE := /tmp/$(project_name)
KERNEL_EXISTS := $(shell test -d $(KERNEL_DIR) && echo 1 || echo 0)
EXEC := KERNEL_VERSION=$(KERNEL_VERSION) TMPFILE=$(TMPFILE) RECOVERY=$(RECOVERY) USE_ALL_CORES=$(USE_ALL_CORES) VERBOSE=$(VERBOSE) PROJECT_DIR=$(PROJECT_DIR) $(SHELL)

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

x86_64: config build-inside-buildenv
aarch64: config build-inside-buildenv

$(WORK_DIR) $(OUTDIR) $(BUILDENV_DIR):
	$(Q)$(MKDIR) -p $@


# this is basically all we have to worry about in this file.
# maybe a better way to figure out if the build-env is downloaded
# or not?
download-build-env: $(BUILDENV_DIR)
ifeq ("$(wildcard $(BUILDENV_DIR)/.hello-world)","")
	@echo "  DOWNLOAD  build-env for $(HOST_ARCH)"
	$(Q)SILENT=$(SILENT) $(EXEC) scripts/download-build-env.sh $(BUILDENV_DIR) $(HOST_ARCH)
else
	@echo "  BUILDENV  (cached)"
endif

build-inside-buildenv: $(WORK_DIR) $(OUTDIR) download-build-env config gen-kconfig gen-config
	$(Q)$(SUDO) $(EXEC) scripts/build-in-buildenv.sh $(BUILDENV_DIR) $(PROJECT_DIR) $(TARGET)

include scripts/make/cleanup.mk
include scripts/make/buildenv.mk