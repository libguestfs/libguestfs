<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output indent="yes" cdata-section-elements="system-out skipped error"/>

<xsl:template match="/">
  <xsl:variable name="TestsTotal"><xsl:value-of select="count(tests/test)"/></xsl:variable>
  <xsl:variable name="TestsPassed"><xsl:value-of select="count(tests/test[@rescode = 0])"/></xsl:variable>
  <xsl:variable name="TestsSkipped"><xsl:value-of select="count(tests/test[@rescode = 77])"/></xsl:variable>
  <xsl:variable name="TestsTimedout"><xsl:value-of select="count(tests/test[@rescode = 124])"/></xsl:variable>
  <xsl:variable name="TestsFailures"><xsl:value-of select="$TestsTotal - $TestsPassed - $TestsSkipped - $TestsTimedout"/></xsl:variable>

<testsuites>
  <testsuite name="libguestfs" tests="{$TestsTotal}" failures="{$TestsFailures}" skipped="{$TestsSkipped}" errors="{$TestsTimedout}">
    <xsl:for-each select="tests/test">
      <xsl:variable name="TestcaseName"><xsl:value-of select="@name"/></xsl:variable>
      <xsl:variable name="TestcaseTime"><xsl:value-of select="@time"/></xsl:variable>
      <xsl:variable name="TestcaseRescode"><xsl:value-of select="@rescode"/></xsl:variable>
      <xsl:variable name="TestcaseClassname"><xsl:choose><xsl:when test="@classname"><xsl:value-of select="@classname"/></xsl:when><xsl:otherwise>TestSuite</xsl:otherwise></xsl:choose></xsl:variable>
      <xsl:variable name="TestcaseOutput"><xsl:value-of select="."/></xsl:variable>
    <testcase name="{$TestcaseName}" classname="{$TestcaseClassname}" time="{$TestcaseTime}">
      <xsl:choose>
        <xsl:when test="$TestcaseRescode = 0">
      <system-out><xsl:value-of select="$TestcaseOutput"/></system-out>
        </xsl:when>
        <xsl:when test="$TestcaseRescode = 77">
      <skipped><xsl:value-of select="$TestcaseOutput"/></skipped>
        </xsl:when>
        <xsl:when test="$TestcaseRescode = 124">
      <error><xsl:value-of select="$TestcaseOutput"/></error>
        </xsl:when>
        <xsl:otherwise>
      <error><xsl:value-of select="$TestcaseOutput"/></error>
        </xsl:otherwise>
      </xsl:choose>
    </testcase>
    </xsl:for-each>
  </testsuite>
</testsuites>

</xsl:template>

</xsl:stylesheet>
