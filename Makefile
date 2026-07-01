ARCHS = arm64
TARGET = iphone:clang::15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NoGamePosts

NoGamePosts_FILES = Tweak.x
NoGamePosts_CFLAGS = -fobjc-arc -Wno-unused-function
NoGamePosts_FRAMEWORKS = UIKit Foundation WebKit

include $(THEOS)/makefiles/tweak.mk
