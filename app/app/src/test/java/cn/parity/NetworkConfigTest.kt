package cn.parity

import cn.openp2p.management.SdwanConfig
import cn.openp2p.management.SdwanMember
import org.junit.Assert.assertEquals
import org.junit.Test
import java.math.BigInteger

class NetworkConfigTest {
    @Test fun recreationSnapshotKeepsUnsavedValuesWithoutSharingMutableMembers() {
        val original = SdwanConfig("10.1.0.0/24", "central", "peer", 1, 2,
            mutableListOf(SdwanMember("peer", "10.1.0.9", "10.2.0.0/24", true)),
            BigInteger("10174872424960844000"), "network1", 1, 4, 1420)
        val retained = original.snapshot()
        assertEquals(original, retained)
        assertEquals("10174872424960844000", retained.id.toString())
        original.gateway = "10.3.0.0/24"
        original.nodes[0].ip = "10.3.0.9"
        original.nodes.clear()
        assertEquals("10.1.0.0/24", retained.gateway)
        assertEquals(SdwanMember("peer", "10.1.0.9", "10.2.0.0/24", true), retained.nodes.single())
        val recreated = retained.snapshot()
        recreated.nodes[0].resource = ""
        assertEquals("10.2.0.0/24", retained.nodes.single().resource)
    }
}
