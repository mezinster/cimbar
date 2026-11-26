package com.shoutsocial.share_handler

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which shares are copied into the cache, and which are refused by size before copying. */
class ContentCopyRuleTest {
  @Test
  fun reportedSizeAboveTheRemainingBudgetIsNotCopied() {
    assertTrue(shouldSkipCopy(reported = SHARE_SIZE_CAP + 1, remaining = SHARE_SIZE_CAP))
    assertTrue(shouldSkipCopy(reported = 11, remaining = 10))
    // A budget already spent by earlier attachments of the same intent.
    assertTrue(shouldSkipCopy(reported = 1, remaining = 0))
  }

  @Test
  fun reportedSizeWithinTheBudgetOrUnreportedIsCopied() {
    assertFalse(shouldSkipCopy(reported = 10, remaining = 10))
    assertFalse(shouldSkipCopy(reported = 0, remaining = SHARE_SIZE_CAP))
    // Unknown size: copied, with copyCapped stopping at the budget.
    assertFalse(shouldSkipCopy(reported = null, remaining = SHARE_SIZE_CAP))
  }

  @Test
  fun onlyContentUrisAreCopied() {
    assertTrue(isContentScheme("content"))
    assertTrue(isContentScheme("CONTENT"))
    assertFalse(isContentScheme("file"))
    assertFalse(isContentScheme(null))
    assertFalse(isContentScheme(""))
  }
}
