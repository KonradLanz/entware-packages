#
# Copyright (C) 2024 Entware
#
# This is free software, licensed under the GNU General Public License v2.
# See /LICENSE for more information.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=rmlint
PKG_VERSION:=2.10.3
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/sahib/rmlint/archive/refs/tags/v$(PKG_VERSION).tar.gz
PKG_HASH:=8ffdbd5d09d15c8717ae55497e90d6fa46f085b45ac1056f2727076da180c33e

PKG_MAINTAINER:=Konrad Lanz
PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_CPE_ID:=cpe:/a:sahib:rmlint

PKG_BUILD_DEPENDS:=scons/host

include $(INCLUDE_DIR)/package.mk
include ../../devel/scons/scons.mk

define Package/rmlint
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Find and remove filesystem lint
  URL:=https://rmlint.readthedocs.io/
  DEPENDS:=+glib2
endef

define Package/rmlint/description
  rmlint finds space waste and other broken things on your filesystem
  and offers to remove it. It is able to find duplicates, empty files,
  broken symlinks and more.
endef

SCONS_OPTIONS += \
	--without-compile-glib-schemas \
	docs=False \
	with_gui=False

define Package/rmlint/install
	$(INSTALL_DIR) $(1)/opt/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/opt/bin/rmlint $(1)/opt/bin/
endef

$(eval $(call BuildPackage,rmlint))
