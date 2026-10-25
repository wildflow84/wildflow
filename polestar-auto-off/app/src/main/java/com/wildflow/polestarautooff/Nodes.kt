package com.wildflow.polestarautooff

import android.accessibilityservice.AccessibilityService
import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo

object Nodes {
    /** Every readable window except our own, so the script never reads its own UI. */
    fun roots(svc: AccessibilityService): List<AccessibilityNodeInfo> {
        val out = mutableListOf<AccessibilityNodeInfo>()
        svc.windows?.forEach { w -> w.root?.let { out.add(it) } }
        if (out.isEmpty()) svc.rootInActiveWindow?.let { out.add(it) }
        return out.filter { it.packageName != svc.packageName }
    }

    private fun norm(s: String) = s.trim().lowercase()

    private fun labelsOf(n: AccessibilityNodeInfo): List<String> =
        listOfNotNull(n.text?.toString(), n.contentDescription?.toString()).map(::norm)

    fun walk(n: AccessibilityNodeInfo, visit: (AccessibilityNodeInfo) -> Unit) {
        visit(n)
        for (i in 0 until n.childCount) n.getChild(i)?.let { walk(it, visit) }
    }

    /** Exact label match wins over a substring match; exactOnly drops the substring fallback. */
    fun find(
        roots: List<AccessibilityNodeInfo>,
        aliases: List<String>,
        exactOnly: Boolean = false,
    ): AccessibilityNodeInfo? {
        val wanted = aliases.map(::norm)
        var partial: AccessibilityNodeInfo? = null
        for (r in roots) {
            var exact: AccessibilityNodeInfo? = null
            walk(r) { n ->
                if (exact == null) {
                    for (l in labelsOf(n)) {
                        if (wanted.any { it == l }) {
                            exact = n
                        } else if (!exactOnly && partial == null && wanted.any { l.contains(it) }) {
                            partial = n
                        }
                    }
                }
            }
            if (exact != null) return exact
        }
        return partial
    }

    /**
     * The switch belonging to a label: climb from the label and take the first ancestor whose subtree
     * holds exactly one checkable node. More than one means we climbed into a neighbouring row.
     */
    fun findToggle(label: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var cur: AccessibilityNodeInfo? = label
        repeat(4) {
            val node = cur ?: return null
            val found = mutableListOf<AccessibilityNodeInfo>()
            walk(node) { if (it.isCheckable) found.add(it) }
            if (found.size == 1) return found[0]
            if (found.size > 1) return null
            cur = node.parent
        }
        return null
    }

    /** The switch under a screen point: the smallest node containing it, or its single checkable descendant/ancestor. */
    fun toggleAt(roots: List<AccessibilityNodeInfo>, x: Int, y: Int): AccessibilityNodeInfo? {
        var best: AccessibilityNodeInfo? = null
        var bestArea = Long.MAX_VALUE
        val r = Rect()
        for (root in roots) {
            walk(root) { n ->
                n.getBoundsInScreen(r)
                if (r.contains(x, y)) {
                    val area = r.width().toLong() * r.height()
                    if (area < bestArea) {
                        best = n
                        bestArea = area
                    }
                }
            }
        }
        val node = best ?: return null
        if (node.isCheckable) return node
        val below = mutableListOf<AccessibilityNodeInfo>()
        walk(node) { if (it.isCheckable) below.add(it) }
        if (below.size == 1) return below[0]
        var up: AccessibilityNodeInfo? = node.parent
        repeat(2) {
            if (up?.isCheckable == true) return up
            up = up?.parent
        }
        return null
    }

    fun click(n: AccessibilityNodeInfo): Boolean {
        var cur: AccessibilityNodeInfo? = n
        while (cur != null) {
            if (cur.isClickable && cur.isEnabled && cur.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
            cur = cur.parent
        }
        return false
    }

    fun scroll(roots: List<AccessibilityNodeInfo>, forward: Boolean): Boolean {
        val action = if (forward) {
            AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
        } else {
            AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        }
        var done = false
        for (r in roots) {
            walk(r) { if (!done && it.isScrollable) done = it.performAction(action) }
            if (done) break
        }
        return done
    }

    /** Text dump of the visible UI tree, for tuning labels in script.json. */
    fun dump(roots: List<AccessibilityNodeInfo>): String {
        val sb = StringBuilder()
        val bounds = Rect()
        fun rec(n: AccessibilityNodeInfo, depth: Int) {
            n.getBoundsInScreen(bounds)
            val flags = buildString {
                if (n.isClickable) append('c')
                if (n.isCheckable) append(if (n.isChecked) 'K' else 'k')
                if (n.isScrollable) append('s')
            }
            sb.append("  ".repeat(depth))
                .append(n.className?.toString()?.substringAfterLast('.'))
                .append(" [").append(flags).append(']')
            n.text?.let { sb.append(" text=\"").append(it).append('"') }
            n.contentDescription?.let { sb.append(" desc=\"").append(it).append('"') }
            n.viewIdResourceName?.let { sb.append(" id=").append(it) }
            sb.append(" bounds=").append(bounds.left).append(',').append(bounds.top)
                .append(',').append(bounds.right).append(',').append(bounds.bottom)
            sb.append('\n')
            for (i in 0 until n.childCount) n.getChild(i)?.let { rec(it, depth + 1) }
        }
        for (r in roots) {
            sb.append("== window ").append(r.packageName).append('\n')
            rec(r, 0)
        }
        return sb.toString()
    }
}
