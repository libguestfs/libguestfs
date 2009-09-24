# libguestfs examples

noinst_PROGRAMS = hello to-xml

hello_SOURCES = hello.c
hello_CFLAGS = -I$(top_srcdir)/src -I$(top_builddir)/src -Wall
hello_LDADD = $(top_builddir)/src/libguestfs.la

to_xml_SOURCES = to-xml.c
to_xml_CPPFLAGS = \
  -I$(top_srcdir)/gnulib/lib \
  -I$(top_srcdir)/src -I$(top_builddir)/src -Wall
to_xml_LDADD = $(top_builddir)/src/libguestfs.la

CLEANFILES = $(noinst_PROGRAMS)
