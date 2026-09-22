TARGET := macosx:clang:latest:15.0
ARCHS = arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = dockpid

dockpid_FRAMEWORKS = Foundation AppKit
dockpid_FILES = Tweak.x
# TI_Support provides PSPreferences / PSUserDefaults, the shared tweak
# preference store. -L only tells the LINKER where to find the library at build
# time. At load time dyld resolves the absolute install name recorded in the
# tweak -- /Library/TweakInject/TI_Support.dylib -- with no search path involved.
SUPPORT := $(dir $(lastword $(MAKEFILE_LIST)))../../XCode-projects/DYLIB/TI_Support

dockpid_CFLAGS = -fobjc-arc -fno-modules -Werror -Wunused-value -I$(SUPPORT)
dockpid_LDFLAGS = -L/Library/TweakInject -lTI_Support

include $(THEOS_MAKE_PATH)/tweak.mk
