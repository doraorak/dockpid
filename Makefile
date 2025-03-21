TARGET := macosx:clang:latest:15.0
ARCHS = arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = dockpid

dockpid_FRAMEWORKS = Foundation
dockpid_FILES = Tweak.x
dockpid_CFLAGS = -fobjc-arc -Werror -Wunused-value

include $(THEOS_MAKE_PATH)/tweak.mk
