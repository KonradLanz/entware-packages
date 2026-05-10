#
# Copyright (C) 2026 Konrad Lanz <konrad@greev.com>
#

include $(TOPDIR)/rules.mk

PKG_NAME:=gh
PKG_VERSION:=2.72.0
PKG_RELEASE:=1

ifeq ($(ARCH),x86_64)
  PKG_ARCH_SUFFIX:=linux_amd64
  PKG_HASH:=ffd3a9791075cf6119531302b06554e658f38ed12675a7fbfbf4d6b114c77f38
else ifeq ($(ARCH),aarch64)
  PKG_ARCH_SUFFIX:=linux_arm64
  PKG_HASH:=30d3b41200b7a195c340d0f121bd214450a10770e4e5164fbf76540a8a68e384
else ifeq ($(ARCH),arm)
  PKG_ARCH_SUFFIX:=linux_armv6
  PKG_HASH:=a505a64e16619f146c1abe7002a083d91a6bd05a4bda166c6c8f9005897613b2
else
  PKG_ARCH_SUFFIX:=linux_amd64
  PKG_HASH:=ffd3a9791075cf6119531302b06554e658f38ed12675a7fbfbf4d6b114c77f38
endif

PKG_SOURCE:=$(PKG_NAME)_$(PKG_VERSION)_$(PKG_ARCH_SUFFIX).tar.gz
PKG_SOURCE_URL:=@GITHUB/cli/cli/releases/download/v$(PKG_VERSION)/

PKG_MAINTAINER:=Konrad Lanz <konrad@greev.com>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=GitHub CLI
  URL:=https://cli.github.com
  DEPENDS:=@(x86_64||aarch64||arm)
endef

define Package/$(PKG_NAME)/description
  GitHub's official command line tool.
  Brings pull requests, issues, releases and other
  GitHub concepts to the terminal.
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/opt/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/gh $(1)/opt/bin/gh
	$(INSTALL_DIR) $(1)/opt/share/$(PKG_NAME)
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENSE $(1)/opt/share/$(PKG_NAME)/LICENSE
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
