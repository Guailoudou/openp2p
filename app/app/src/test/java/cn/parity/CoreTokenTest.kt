package cn.parity

import cn.openp2p.security.tokenValidationError

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreTokenTest {
    @Test fun tokenMatchesHarmonyUnsigned64BitRules() {
        listOf("1", "0001", "18446744073709551615", "00018446744073709551615").forEach {
            assertEquals(it, "", tokenValidationError(it))
        }
        listOf("", "0", "000", "-1", "+1", "1.0", " 1", "1e3", "18446744073709551616").forEach {
            assertTrue(it, tokenValidationError(it).isNotEmpty())
        }
    }
}
