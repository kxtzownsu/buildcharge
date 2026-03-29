## directories ##
PROJECT_DIR := $(abspath .)
WORK_DIR := $(abspath $(PROJECT_DIR)/build/)
CONFDIR := $(abspath $(PROJECT_DIR)/configs/)
OUTDIR := $(abspath $(PROJECT_DIR)/out/)
BUILDENV_DIR := $(abspath $(WORK_DIR)/build-env/)
KERNEL_BUILD_DIR := $(WORK_DIR)/kernel/$(TARGET)/
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



## files ##
INITFS_CPIO := $(WORK_DIR)/ramfs/$(project_name).$(TARGET).cpio
INITFS_CPIOZ := $(INITFS_CPIO).xz
KPART := $(WORK_DIR)/$(project_name).$(TARGET).kpart
IMG := $(WORK_DIR)/$(project_name).$(TARGET).bin
BZIMAGE := $(WORK_DIR)/kernel/$(project_name).$(TARGET).bzImage