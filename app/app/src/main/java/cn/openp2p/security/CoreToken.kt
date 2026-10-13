package cn.openp2p.security

fun tokenValidationError(value: String): String {
    if (!value.matches(Regex("[0-9]+"))) return "Token 只能包含十进制数字"
    val normalized = value.trimStart('0')
    if (normalized.isEmpty()) return "Token 不能为 0"
    val maximum = "18446744073709551615"
    if (normalized.length > maximum.length ||
        (normalized.length == maximum.length && normalized > maximum)) return "Token 超出 uint64 范围"
    return ""
}
