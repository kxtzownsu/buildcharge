KEYDIR := /usr/share/vboot/devkeys
KEYEXT := .vbprivk
PUBKEYEXT := .vbpubk
KEYBLOCKEXT := .keyblock
# reco-signed kernels dont work on depthchargectl due to a bug.
ifneq ($(TARGET),aarch64)
ifeq ($(RECOVERY),1)
DATA_KEY := $(KEYDIR)/recovery_kernel_data_key$(KEYEXT)
PUB_DATA_KEY := $(KEYDIR)/recovery_kernel_data_key$(PUBKEYEXT)
KEYBLOCK := $(KEYDIR)/recovery_kernel$(KEYBLOCKEXT) 
endif
endif
ifneq ($(RECOVERY),1)
DATA_KEY := $(KEYDIR)/kernel_data_key$(KEYEXT)
PUB_DATA_KEY := $(KEYDIR)/kernel_data_key$(PUBKEYEXT)
KEYBLOCK := $(KEYDIR)/kernel$(KEYBLOCKEXT) 
endif

ifeq ($(TARGET),aarch64)
# hardcode regular keys, find a better way to do this.
DATA_KEY := $(KEYDIR)/kernel_data_key$(KEYEXT)
PUB_DATA_KEY := $(KEYDIR)/kernel_data_key$(PUBKEYEXT)
KEYBLOCK := $(KEYDIR)/kernel$(KEYBLOCKEXT) 
endif