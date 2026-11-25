package com.shoutsocial.share_handler

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

/** A share above the cap must never be copied in full on the main thread. */
class CappedCopyTest {
  private fun copy(size: Int, cap: Long): Pair<Boolean, ByteArray> {
    val out = ByteArrayOutputStream()
    val ok = copyCapped(ByteArrayInputStream(ByteArray(size) { 7 }), out, cap)
    return ok to out.toByteArray()
  }

  @Test
  fun copiesExactlyCapBytes() {
    val (ok, bytes) = copy(10, 10)
    assertTrue(ok)
    assertArrayEquals(ByteArray(10) { 7 }, bytes)
  }

  @Test
  fun stopsOnceCapIsExceeded() {
    val (ok, bytes) = copy(11, 10)
    assertFalse(ok)
    assertTrue(bytes.size <= 11)
  }

  @Test
  fun stopsEarlyOnLargeStream() {
    val (ok, bytes) = copy(100_000, 10)
    assertFalse(ok)
    assertTrue(bytes.size < 100_000)
  }

  @Test
  fun constantsMatchTheDartSide() {
    assertEquals("cimbar-too-large:", TOO_LARGE_PREFIX)
    assertEquals(134217728L, SHARE_SIZE_CAP)
  }

  @Test
  fun budgetIsOnePerIntentAndNeverNegative() {
    val b = CopyBudget(100)
    assertEquals(100L, b.remaining)
    b.consume(60)
    assertEquals(40L, b.remaining)
    b.consume(1000)
    assertEquals(0L, b.remaining)
    assertEquals(SHARE_SIZE_CAP, CopyBudget().remaining)
  }
}
