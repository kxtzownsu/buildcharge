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