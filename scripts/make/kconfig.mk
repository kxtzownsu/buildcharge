KCONFIG_SCRIPT := bash $(PROJECT_DIR)/scripts/kconfig/kconfig.sh
KCONFIG_FILE   := $(WORK_DIR)/Kconfig
DOT_CONFIG     := $(PROJECT_DIR)/.config
CONFIG_SH      := $(PROJECT_DIR)/scripts/lib/generated/config.sh
CONFIG_MK      := $(PROJECT_DIR)/scripts/lib/generated/config.mk

KCONFIG_FLAGS  := --kconfig $(KCONFIG_FILE) \
                  --dot-config $(DOT_CONFIG) \
                  --config-sh $(CONFIG_SH) \
									--config-mk $(CONFIG_MK) \
                  --manifest $(MANIFEST_JSON)

.PHONY: menuconfig guiconfig gen-manifest gen-kconfig gen-config olddefconfig config

MANIFEST_PRE := $(PROJECT_DIR)/ramfs/manifest/manifest.json.pre

gen-manifest:
	$(Q)$(EXEC) $(PROJECT_DIR)/ramfs/scripts/preprocess-manifest.sh $(MANIFEST_PRE) $(MANIFEST_JSON) $(TARGET)

menuconfig: config gen-kconfig
	$(Q)$(KCONFIG_SCRIPT) menuconfig $(KCONFIG_FLAGS)

guiconfig: config gen-kconfig
	$(Q)$(KCONFIG_SCRIPT) guiconfig $(KCONFIG_FLAGS)

config: gen-manifest
ifneq ($(PROJECT),)
	$(Q)$(COPY) $(PROJECT_DIR)/configs/projects/$(PROJECT)/default.$(TARGET) $(DOT_CONFIG)
else ifeq ($(USE_DEFAULT_CONFIG),1)
	$(Q)$(COPY) $(PROJECT_DIR)/configs/default.$(TARGET) $(DOT_CONFIG)
else
	$(KCONFIG_SCRIPT) check $(KCONFIG_FLAGS)
endif

gen-kconfig: config
	$(Q)$(KCONFIG_SCRIPT) gen-kconfig --manifest $(MANIFEST_JSON) --dot-config $(DOT_CONFIG) --kconfig $(KCONFIG_FILE)

gen-config: config
	$(Q)$(KCONFIG_SCRIPT) gen-config --dot-config $(DOT_CONFIG) \
		--config-sh $(CONFIG_SH) \
		--config-mk $(CONFIG_MK)

olddefconfig:
	$(Q)$(KCONFIG_SCRIPT) olddefconfig $(KCONFIG_FLAGS)

-include $(CONFIG_SH)
