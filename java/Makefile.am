# libguestfs Java bindings
# Copyright (C) 2009-2014 Red Hat Inc.
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

include $(top_srcdir)/subdir-rules.mk

java_prefix = com/redhat/et/libguestfs

generator_built = \
	Makefile.inc \
	$(java_built_sources) \
	com_redhat_et_libguestfs_GuestFS.c \
	$(srcdir)/Bindtests.java

# Pull in automatically generated built sources
include $(srcdir)/Makefile.inc

java_sources = \
	$(java_built_sources) \
	com/redhat/et/libguestfs/EventCallback.java \
	com/redhat/et/libguestfs/LibGuestFSException.java

java_tests = \
	Bindtests.java \
	t/GuestFS010Load.java \
	t/GuestFS020Create.java \
	t/GuestFS030CreateFlags.java \
	t/GuestFS040CreateMultiple.java \
	t/GuestFS050HandleProperties.java \
	t/GuestFS070OptArgs.java \
	t/GuestFS100Launch.java \
	t/GuestFS410CloseEvent.java \
	t/GuestFS420LogMessages.java \
	t/GuestFS430ProgressMessages.java \
	t/GuestFS800RHBZ1073906.java

EXTRA_DIST = \
	com/redhat/et/libguestfs/.gitignore \
	$(java_sources) \
	$(java_tests) \
	run-bindtests \
	run-java-tests \
	Makefile.inc

CLEANFILES = \
	doc-stamp \
	com/redhat/et/libguestfs/*.class \
	com_redhat_et_libguestfs_GuestFS.h \
	*.class \
	*.jar

clean-local:
	-rm -rf api

if HAVE_JAVA

JAVAC_FLAGS = $(EXTRA_JAVAC_FLAGS) -encoding utf-8
JAVADOC_FLAGS = -encoding utf-8

# Java source.

libguestfs_jardir = $(JAR_INSTALL_DIR)
libguestfs_jar_DATA = libguestfs-${VERSION}.jar
libguestfs_jar_class_files = $(java_sources:.java=.class)
$(libguestfs_jar_class_files): %.class: %.java
	$(JAVAC) $(JAVAC_FLAGS) -d . -classpath $(srcdir):. $<

libguestfs-${VERSION}.jar: $(libguestfs_jar_class_files)
	$(JAR) cf $@ $^

# JNI source.

jnilib_LTLIBRARIES = libguestfs_jni.la

jnilibdir = $(JNI_INSTALL_DIR)

libguestfs_jni_la_SOURCES = \
	com_redhat_et_libguestfs_GuestFS.h \
	com_redhat_et_libguestfs_GuestFS.c

libguestfs_jni_la_CPPFLAGS = \
	-DGUESTFS_PRIVATE=1 \
	-I$(top_srcdir)/src -I$(top_builddir)/src

libguestfs_jni_la_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(JNI_CFLAGS)

libguestfs_jni_la_LIBADD = $(top_builddir)/src/libguestfs.la

libguestfs_jni_la_LDFLAGS = -version-info $(JNI_VERSION_INFO) -shared

BUILT_SOURCES = com_redhat_et_libguestfs_GuestFS.h

com_redhat_et_libguestfs_GuestFS.h: $(java_prefix)/GuestFS.class
	rm -f $@
	$(JAVAH) -classpath $(srcdir):. com.redhat.et.libguestfs.GuestFS

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
	mkdir -p $(DESTDIR)$(datadir)/javadoc/$(PACKAGE_NAME)
	cp -a api/* $(DESTDIR)$(datadir)/javadoc/$(PACKAGE_NAME)

# Tests (not comprehensive).

TESTS = run-bindtests
if ENABLE_APPLIANCE
TESTS += run-java-tests
endif ENABLE_APPLIANCE

TESTS_ENVIRONMENT = $(top_builddir)/run --test

noinst_DATA = Bindtests.class $(java_tests:.java=.class)

t/%.class: t/%.java libguestfs-$(VERSION).jar
	$(JAVAC) $(JAVAC_FLAGS) -classpath libguestfs-$(VERSION).jar -d t $<

Bindtests.class: Bindtests.java libguestfs-$(VERSION).jar
	$(JAVAC) $(JAVAC_FLAGS) -classpath libguestfs-$(VERSION).jar -d . $<

endif
