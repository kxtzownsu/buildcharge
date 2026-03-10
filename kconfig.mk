KCONFIG_SCRIPT := bash $(PROJECT_DIR)/scripts/kconfig/kconfig.sh
KCONFIG_FILE   := $(WORK_DIR)/Kconfig
DOT_CONFIG     := $(PROJECT_DIR)/.config
CONFIG_SH      := $(PROJECT_DIR)/scripts/lib/generated/config.sh

.PHONY: menuconfig guiconfig gen-kconfig gen-config olddefconfig

menuconfig: gen-kconfig
	@echo "  MENUCONFIG"
	$(Q)$(KCONFIG_SCRIPT) menuconfig

guiconfig: gen-kconfig
	@echo "  GUICONFIG"
	$(Q)$(KCONFIG_SCRIPT) guiconfig

config: gen-kconfig
	@echo "  CONFIG    .config"
	$(Q)$(KCONFIG_SCRIPT) check

gen-kconfig:
	$(Q)bash scripts/kconfig/gen-kconfig.sh $(PROJECT_DIR)/ramfs/manifest.json

gen-config:
	@echo "  GEN-CONFIG"
	$(Q)$(KCONFIG_SCRIPT) gen-config

olddefconfig: gen-kconfig
	@echo "  OLDDEFCONFIG"
	$(Q)$(KCONFIG_SCRIPT) olddefconfig

-include $(CONFIG_SH)