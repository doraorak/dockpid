TARGET := macosx:clang:latest:15.0
ARCHS = arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = dockpid

dockpid_FRAMEWORKS = Foundation AppKit
dockpid_FILES = Tweak.x
# libprefSupport provides PSPreferences / PSUserDefaults, the shared tweak
# preference store. Headers come from the tweakLoader source tree; -L only tells
# the LINKER where to find the library at build time. At load time dyld resolves
# the absolute install name recorded in the tweak -- /Library/TweakInject/... --
# with no search path involved.
PREFSUPPORT := $(dir $(lastword $(MAKEFILE_LIST)))../../XCode-projects/DYLIB/TI_PreferenceSupport

dockpid_CFLAGS = -fobjc-arc -fno-modules -Werror -Wunused-value -I$(PREFSUPPORT)
dockpid_LDFLAGS = -L/Library/TweakInject -lTI_PreferenceSupport

include $(THEOS_MAKE_PATH)/tweak.mk
