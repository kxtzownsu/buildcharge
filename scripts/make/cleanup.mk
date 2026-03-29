cleanup-buildenv:
	@echo "  UNMOUNT"
	$(Q)$(SUDO) $(EXEC) scripts/cleanup-orphaned-mounts.sh $(PROJECT_DIR)

cleanup-all:
	@echo "  UNMOUNT"
	$(Q)$(SUDO) $(EXEC) scripts/cleanup-orphaned-mounts.sh $(project_name)

clean:
	@echo "The typical 'make clean' does not work with buildcharge."
	@echo "You must use 'make clean-[arch], for example: make clean-x86_64 or make clean-aarch64"

clean-arm64: clean-aarch64

clean-x86_64 clean-aarch64:
	$(Q)$(MAKE) TARGET=$(TARGET) internal_clean

internal_clean:
	@echo "  SUDORM    $(BZIMAGE)"
	$(Q)$(SUDO) $(RM) -rf $(BZIMAGE)
	@echo "  SUDORM    $(INITFS_CPIO)"
	$(Q)$(SUDO) $(RM) -rf $(INITFS_CPIO)
	@echo "  SUDORM    $(INITFS_CPIOZ)"
	$(Q)$(SUDO) $(RM) -rf $(INITFS_CPIOZ)
	@echo "  SUDORM    $(KPART)"
	$(Q)$(SUDO) $(RM) -rf $(KPART)
	@echo "  SUDORM    $(INITFS_DIR)"
	$(Q)$(SUDO) $(RM) -rf $(INITFS_DIR)

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