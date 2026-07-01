THEOS_DEVICE_IP = 0.0.0.0
ARCHS = arm64
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NoGamePosts

NoGamePosts_FILES = Tweak.x
NoGamePosts_CFLAGS = -fobjc-arc
NoGamePosts_FRAMEWORKS = UIKit Foundation WebKit

include $(THEOS)/makefiles/tweak.mk
