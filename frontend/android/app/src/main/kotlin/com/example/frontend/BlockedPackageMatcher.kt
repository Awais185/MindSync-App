package com.example.frontend

/**
 * Maps alternate package ids (e.g. TikTok regional builds) so a block on one id
 * covers every installed variant.
 */
object BlockedPackageMatcher {
    private val aliasGroups: List<Set<String>> =
        listOf(
            TrackedSocialApps.tikTokPackages,
            setOf(TrackedSocialApps.TWITTER, TrackedSocialApps.TWITTER_ALT),
            TrackedSocialApps.whatsAppPackages,
        )

    fun expandPackages(packages: Collection<String>): Set<String> {
        val out = HashSet<String>()
        for (pkg in packages) {
            val trimmed = pkg.trim()
            if (trimmed.isBlank()) continue
            out.add(trimmed)
            for (group in aliasGroups) {
                if (group.contains(trimmed)) {
                    out.addAll(group)
                    break
                }
            }
        }
        return out
    }

    fun isBlocked(foregroundPackage: String?, blockedPackages: Set<String>): Boolean {
        val fg = foregroundPackage?.trim().orEmpty()
        if (fg.isBlank() || blockedPackages.isEmpty()) return false
        if (blockedPackages.contains(fg)) return true
        for (group in aliasGroups) {
            if (!group.contains(fg)) continue
            if (group.any { blockedPackages.contains(it) }) return true
        }
        return false
    }
}
