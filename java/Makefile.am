# libguestfs Java bindings
# Copyright (C) 2009 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

CPTH = com/redhat/et/libguestfs

java_sources = \
	$(CPTH)/LibGuestFSException.java \
	$(CPTH)/IntBool.java \
	$(CPTH)/PV.java \
	$(CPTH)/VG.java \
	$(CPTH)/LV.java \
	$(CPTH)/Stat.java \
	$(CPTH)/StatVFS.java \
	$(CPTH)/GuestFS.java

java_tests = \
	t/GuestFS005Load.java \
	t/GuestFS010Launch.java \
	t/GuestFS050LVCreate.java

EXTRA_DIST = \
	$(java_sources) \
	$(java_tests) \
	run-java-test

CLEANFILES = doc-stamp

if HAVE_JAVA

# Java source.

libguestfs_jardir = $(JAR_INSTALL_DIR)
libguestfs_jar_DATA = libguestfs-${VERSION}.jar
libguestfs_jar_class_files = $(java_sources:.java=.class)
$(libguestfs_jar_class_files): %.class: %.java
	$(JAVAC) $(JAVAC_FLAGS) -classpath $(CPTH) $(java_sources)

libguestfs-${VERSION}.jar: $(libguestfs_jar_class_files)
	$(JAR) cf $@ $^

# JNI source.

lib_LTLIBRARIES = libguestfs_jni.la
libguestfs_jni_la_SOURCES = \
	com_redhat_et_libguestfs_GuestFS.h \
	com_redhat_et_libguestfs_GuestFS.c

libguestfs_jni_la_LIBADD = $(top_builddir)/src/libguestfs.la
libguestfs_jni_la_LDFLAGS = -version-info $(JNI_VERSION_INFO)
libguestfs_jni_la_CFLAGS = -Wall -I$(top_builddir)/src $(JNI_CFLAGS)

BUILT_SOURCES = com_redhat_et_libguestfs_GuestFS.h

com_redhat_et_libguestfs_GuestFS.h: $(CPTH)/GuestFS.class
	$(JAVAH) -classpath .:$(CPTH) com.redhat.et.libguestfs.GuestFS

# Documentation.

noinst_SCRIPTS = doc-stamp

doc-stamp: $(java_sources)
	$(JAVADOC) $(JAVADOC_FLAGS) -d api \
	  -sourcepath $(srcdir) \
	  -windowtitle "libguestfs java $(VERSION) API reference" \
	  -doctitle "libguestfs java $(VERSION) API reference" \
	  com.redhat.et.libguestfs
	touch $@

install-data-hook:
	mkdir -p $(DESTDIR)$(datadir)/javadoc/$(PACKAGE_NAME)-java-$(PACKAGE_VERSION)
	cp -a api/* $(DESTDIR)$(datadir)/javadoc/$(PACKAGE_NAME)-java-$(PACKAGE_VERSION)

# Tests (not comprehensive).

TESTS = $(java_tests:.java=.class)
TESTS_ENVIRONMENT = \
	JAVA=$(JAVA) \
	CLASSPATH=t:libguestfs-$(VERSION).jar \
	LIBGUESTFS_PATH=$(top_builddir)/appliance \
	./run-java-test

t/%.class: t/%.java
	$(JAVAC) $(JAVAC_FLAGS) -classpath libguestfs-$(VERSION).jar $<

endif

# Tell version 3.79 and up of GNU make to not build goals in this
# directory in parallel.
.NOTPARALLEL:
