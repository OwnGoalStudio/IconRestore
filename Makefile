export PACKAGE_VERSION := 1.6

ifeq ($(THEOS_DEVICE_SIMULATOR),1)
TARGET := simulator:clang:latest:14.0
ARCHS := arm64
IPHONE_SIMULATOR_ROOT := $(shell devkit/sim-root.sh)
export IPHONE_SIMULATOR_ROOT
else
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES := SpringBoard
ARCHS := arm64 arm64e
endif

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += IconRestorePrefs

include $(THEOS_MAKE_PATH)/aggregate.mk

TWEAK_NAME := IconRestore

IconRestore_FILES += IconRestore.x
IconRestore_CFLAGS += -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

export THEOS_OBJ_DIR
after-all::
	@devkit/sim-install.sh
