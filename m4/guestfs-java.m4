# libguestfs
# Copyright (C) 2009-2023 Red Hat Inc.
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

dnl Check for Java.
AC_ARG_WITH(java,
    [AS_HELP_STRING([--with-java],
        [specify path to JDK directory (for the Java language bindings) @<:@default=check@:>@])],
    [],
    [with_java=check])

if test "x$with_java" != "xno"; then
    if test "x$with_java" != "xyes" && test "x$with_java" != "xcheck"
    then
        # Reject unsafe characters in $JAVA
        jh_lf='
'
        case $JAVA in
          *[\\\"\#\$\&\'\`$jh_lf\ \	]*)
            AC_MSG_FAILURE([unsafe \$JAVA directory (use --without-java to disable Java support)]);;
        esac
        if test -d "$with_java"; then
            JAVA="$with_java"
        else
            AC_MSG_FAILURE([$with_java is not a directory (use --without-java to disable Java support)])
        fi
    fi

    if test "x$JAVA" = "x"; then
        # Look for Java in some likely locations.
        for d in \
            /usr/lib/jvm/java \
            /usr/lib64/jvm/java \
            /usr/lib/jvm/default-java \
            /usr/lib/jvm/default \
            /etc/java-config-2/current-system-vm \
            /usr/lib/jvm/java-8-openjdk \
            /usr/lib/jvm/java-7-openjdk \
            /usr/lib/jvm/java-6-openjdk
        do
            AC_MSG_CHECKING([for 'java' in $d])
            if test -d $d && test -f $d/bin/java; then
                AC_MSG_RESULT([found])
                JAVA=$d
                break
            else
                AC_MSG_RESULT([not found])
            fi
        done
    fi

    if test "x$JAVA" != "x"; then
        AC_MSG_CHECKING(for JDK in $JAVA)
        if test ! -x "$JAVA/bin/java"; then
            AC_MSG_ERROR([missing $JAVA/bin/java binary (use --without-java to disable Java support)])
        else
            JAVA_EXE="$JAVA/bin/java"
        fi
        if test ! -x "$JAVA/bin/javac"; then
            AC_MSG_ERROR([missing $JAVA/bin/javac binary])
        else
            JAVAC="$JAVA/bin/javac"
        fi
        if test -x "$JAVA/bin/javah"; then
            JAVAH="$JAVA/bin/javah"
        fi
        if test ! -x "$JAVA/bin/javadoc"; then
            AC_MSG_ERROR([missing $JAVA/bin/javadoc binary])
        else
            JAVADOC="$JAVA/bin/javadoc"
        fi
        if test ! -x "$JAVA/bin/jar"; then
            AC_MSG_ERROR([missing $JAVA/bin/jar binary])
        else
            JAR="$JAVA/bin/jar"
        fi
        java_version=`$JAVA_EXE -version 2>&1 | $AWK -F '"' '/^(java|openjdk) version/ {print $2;}'`
        AC_MSG_RESULT(found $java_version)

        dnl Find jni.h.
        AC_MSG_CHECKING([for jni.h])
        if test -f "$JAVA/include/jni.h"; then
            JNI_CFLAGS="-I$JAVA/include"
        else
            if test "`find $JAVA -name jni.h`" != ""; then
                head=`find $JAVA -name jni.h | tail -1`
                dir=`dirname "$head"`
                JNI_CFLAGS="-I$dir"
            else
                AC_MSG_FAILURE([missing jni.h header file])
            fi
        fi
        AC_MSG_RESULT([$JNI_CFLAGS])

        dnl Find jni_md.h.
        AC_MSG_CHECKING([for jni_md.h])
        case "$build_os" in
        *linux*) system="linux" ;;
        *SunOS*) system="solaris" ;;
        *cygwin*) system="win32" ;;
        *) system="$build_os" ;;
        esac
        if test -f "$JAVA/include/$system/jni_md.h"; then
            JNI_CFLAGS="$JNI_CFLAGS -I$JAVA/include/$system"
        else
            if test "`find $JAVA -name jni_md.h`" != ""; then
                head=`find $JAVA -name jni_md.h | tail -1`
                dir=`dirname "$head"`
                JNI_CFLAGS="$JNI_CFLAGS -I$dir"
            else
                AC_MSG_FAILURE([missing jni_md.h header file])
            fi
        fi
        AC_MSG_RESULT([$JNI_CFLAGS])

        dnl Extra lint flags?
        AC_MSG_CHECKING([extra javac lint flags])
        if $JAVAC -X >/dev/null 2>&1 && \
           $JAVAC -X 2>&1 | grep -q -- '-Xlint:.*all'; then
            AC_MSG_RESULT([-Xlint:all])
            EXTRA_JAVAC_FLAGS="$EXTRA_JAVAC_FLAGS -Xlint:all"
        else
            AC_MSG_RESULT([no])
        fi

        dnl Where to install jarfiles, jnifiles
        if test -z $JAR_INSTALL_DIR; then
            JAR_INSTALL_DIR=\${prefix}/share/java
        fi
        if test -z $JNI_INSTALL_DIR; then
            JNI_INSTALL_DIR=\${libdir}
        fi

        dnl JNI version.
        jni_major_version=`echo "$VERSION" | $AWK -F. '{print $1}'`
        jni_minor_version=`echo "$VERSION" | $AWK -F. '{print $2}'`
        jni_micro_version=`echo "$VERSION" | $AWK -F. '{print $3}'`
        JNI_VERSION_INFO=`expr "$jni_major_version" + "$jni_minor_version"`":$jni_micro_version:$jni_minor_version"
    fi

    AC_SUBST(JAVA)
    AC_SUBST(JAVA_EXE)
    AC_SUBST(JAVAC)
    AC_SUBST(JAVAH)
    AC_SUBST(JAVADOC)
    AC_SUBST(JAR)
    AC_SUBST(JNI_CFLAGS)
    AC_SUBST(EXTRA_JAVAC_FLAGS)
    AC_SUBST(JAR_INSTALL_DIR)
    AC_SUBST(JNI_INSTALL_DIR)
    AC_SUBST(JNI_VERSION_INFO)
fi

AM_CONDITIONAL([HAVE_JAVAH],[test -n "$JAVAH"])
AM_CONDITIONAL([HAVE_JAVA],[test "x$with_java" != "xno" && test -n "$JAVAC"])
