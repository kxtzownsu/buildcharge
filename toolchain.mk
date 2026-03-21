HOST_ARCH := $(shell uname -m)
TARGET ?=
CROSS_COMPILE ?=
BUILDENV ?=
VERBOSE := 0

# We expect `VERBOSE=1`, nothing else.
ifeq ($(VERBOSE),1)
Q :=
else
Q := @
endif

ifeq ($(TARGET),arm64)
ARCH := aarch64
else ifeq ($(TARGET),x86_64)
ARCH := x86_64
else
ARCH := $(TARGET)
endif

# wow... holy nesting..
ifeq ($(CROSS_COMPILE),)
ifneq ($(TARGET),)
  # Building for x86_64 target
  ifeq ($(TARGET),x86_64)
    ifneq ($(HOST_ARCH),x86_64)
      # Cross-compiling TO x86_64
      ifeq ($(BUILDENV),1)
				TOOLCHAIN := x86_64-linux-musl
        CROSS_COMPILE := /opt/cross/$(TOOLCHAIN)/bin/$(TOOLCHAIN)-
      else
        CROSS_COMPILE := x86_64-linux-gnu-
      endif
    endif
  endif
  # Building for arm64 target
  ifeq ($(TARGET),arm64)
    ifneq ($(HOST_ARCH),aarch64)
      # Cross-compiling TO arm64
      ifeq ($(BUILDENV),1)
				TOOLCHAIN := aarch64-linux-musl
        CROSS_COMPILE := /opt/cross/$(TOOLCHAIN)/bin/$(TOOLCHAIN)-
			else
        CROSS_COMPILE := aarch64-linux-gnu-
      endif
    endif
  endif
endif
endif

### Build utilities ###
MAKE ?= make
SHELL := /bin/bash
CC := $(CROSS_COMPILE)gcc
CXX := $(CROSS_COMPILE)g++
AS := $(CROSS_COMPILE)as
LD := $(CROSS_COMPILE)ld
AR := $(CROSS_COMPILE)ar
OBJCOPY := $(CROSS_COMPILE)objcopy
STRIP := $(CROSS_COMPILE)strip

### Standard utilities ###
SUDO ?= sudo
COPY ?= cp
MOVE ?= mv
RM ?= rm
MKDIR ?= mkdir
TOUCH ?= touch
CHMOD ?= chmod
CHOWN ?= chown