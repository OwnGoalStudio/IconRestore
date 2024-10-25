ifeq ($(THEOS_DEVICE_SIMULATOR),1)
TARGET := simulator:clang:latest:14.0
ARCHS := arm64
else
TARGET := iphone:clang:16.5:14.0
INSTALL_TARGET_PROCESSES := Preferences
ARCHS := arm64 arm64e
endif

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME := IconRestorePrefs

IconRestorePrefs_FILES += IconRestoreRootListController.m
IconRestorePrefs_CFLAGS += -fobjc-arc

ifeq ($(THEOS_DEVICE_SIMULATOR),1)
IconRestorePrefs_FILES += ../libroot/dyn.c
IconRestorePrefs_CFLAGS += -DIPHONE_SIMULATOR_ROOT=\"$(IPHONE_SIMULATOR_ROOT)\"
IconRestorePrefs_LDFLAGS += -FLibrary/_Simulator
endif

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
IconRestorePrefs_FILES += ../libroot/dyn.c
endif

IconRestorePrefs_FRAMEWORKS += UIKit
IconRestorePrefs_PRIVATE_FRAMEWORKS += CoreServices
IconRestorePrefs_PRIVATE_FRAMEWORKS += Preferences
IconRestorePrefs_INSTALL_PATH += /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk