KCONFIG_SCRIPT := bash $(PROJECT_DIR)/scripts/kconfig/kconfig.sh
KCONFIG_FILE   := $(WORK_DIR)/Kconfig
DOT_CONFIG     := $(PROJECT_DIR)/.config
CONFIG_SH      := $(PROJECT_DIR)/scripts/lib/generated/config.sh

KCONFIG_FLAGS  := --kconfig $(KCONFIG_FILE) \
                  --dot-config $(DOT_CONFIG) \
                  --config-sh $(CONFIG_SH) \
                  --manifest $(PROJECT_DIR)/ramfs/manifest.json

.PHONY: menuconfig guiconfig gen-kconfig gen-config olddefconfig config

menuconfig:
	$(Q)$(KCONFIG_SCRIPT) menuconfig $(KCONFIG_FLAGS)

guiconfig:
	$(Q)$(KCONFIG_SCRIPT) guiconfig $(KCONFIG_FLAGS)

config:
	$(Q)if [ "$(USE_DEFAULT_CONFIG)" = "1" ]; then \
		cp $(PROJECT_DIR)/configs/default.$(TARGET) $(DOT_CONFIG); \
	else \
		$(KCONFIG_SCRIPT) check $(KCONFIG_FLAGS); \
	fi

gen-kconfig:
	$(Q)$(KCONFIG_SCRIPT) gen-kconfig --manifest $(PROJECT_DIR)/ramfs/manifest.json --kconfig $(KCONFIG_FILE)

gen-config:
	$(Q)$(KCONFIG_SCRIPT) gen-config --dot-config $(DOT_CONFIG) --config-sh $(CONFIG_SH)

olddefconfig:
	$(Q)$(KCONFIG_SCRIPT) olddefconfig $(KCONFIG_FLAGS)

-include $(CONFIG_SH)