/* =============================================================================
 * SourceLess OS - Anaconda WebUI Runtime Branding & Cyber HUD Injector
 * Enforces dark theme classes, renders the LockScreen-style top HUD, and
 * scrubs residual Fedora/Kinoite strings or logo assets from live React DOM.
 * ============================================================================= */

(function () {
    "use strict";

    var BRAND_LOGO = "./logo.svg";

    // Enforce PatternFly 5 & 6 dark theme classes on html and body
    function enforceDarkClasses() {
        var root = document.documentElement;
        if (root) {
            if (!root.classList.contains("pf-v5-theme-dark")) {
                root.classList.add("pf-v5-theme-dark");
            }
            if (!root.classList.contains("pf-v6-theme-dark")) {
                root.classList.add("pf-v6-theme-dark");
            }
            root.style.colorScheme = "dark";
        }
        if (document.body) {
            if (!document.body.classList.contains("pf-v5-theme-dark")) {
                document.body.classList.add("pf-v5-theme-dark");
            }
            if (!document.body.classList.contains("pf-v6-theme-dark")) {
                document.body.classList.add("pf-v6-theme-dark");
            }
        }
        if (document.title && /fedora|kinoite/i.test(document.title)) {
            document.title = "SourceLess OS Installer";
        }
    }

    // Format HUD date/time to match LockScreenUi.qml ("ddd, dd MMM yyyy" and "HH:mm:ss")
    function updateHudClock(dateEl, timeEl) {
        var now = new Date();
        try {
            var weekday = now.toLocaleDateString("en-US", { weekday: "short" });
            var day = String(now.getDate()).padStart(2, "0");
            var month = now.toLocaleDateString("en-US", { month: "short" });
            var year = now.getFullYear();
            dateEl.textContent = weekday + ", " + day + " " + month + " " + year;

            var hh = String(now.getHours()).padStart(2, "0");
            var mm = String(now.getMinutes()).padStart(2, "0");
            var ss = String(now.getSeconds()).padStart(2, "0");
            timeEl.textContent = hh + ":" + mm + ":" + ss;
        } catch (e) {
            dateEl.textContent = now.toDateString();
            timeEl.textContent = now.toTimeString().slice(0, 8);
        }
    }

    // Insert the LockScreen-inspired Top Cyber HUD Bar once
    function ensureTopHud() {
        if (!document.body || document.getElementById("sl-cyber-hud")) {
            return;
        }

        var hud = document.createElement("header");
        hud.id = "sl-cyber-hud";

        var left = document.createElement("div");
        left.className = "sl-hud-left";

        var logo = document.createElement("img");
        logo.className = "sl-hud-logo";
        logo.src = BRAND_LOGO;
        logo.alt = "SourceLess OS";
        logo.onerror = function () {
            logo.style.display = "none";
        };

        var title = document.createElement("span");
        title.className = "sl-hud-title";
        title.textContent = "SOURCELESS OS";

        var sep1 = document.createElement("span");
        sep1.className = "sl-hud-sep";

        var dot = document.createElement("span");
        dot.className = "sl-hud-dot";

        var subtitle = document.createElement("span");
        subtitle.className = "sl-hud-subtitle";
        subtitle.textContent = "SYSTEM INSTALLER // DEPLOYMENT";

        left.appendChild(logo);
        left.appendChild(title);
        left.appendChild(sep1);
        left.appendChild(dot);
        left.appendChild(subtitle);

        var right = document.createElement("div");
        right.className = "sl-hud-right";

        var dateEl = document.createElement("span");
        dateEl.className = "sl-hud-date";

        var sep2 = document.createElement("span");
        sep2.className = "sl-hud-sep";

        var timeEl = document.createElement("span");
        timeEl.className = "sl-hud-time";

        right.appendChild(dateEl);
        right.appendChild(sep2);
        right.appendChild(timeEl);

        hud.appendChild(left);
        hud.appendChild(right);

        document.body.insertBefore(hud, document.body.firstChild);
        updateHudClock(dateEl, timeEl);
        setInterval(function () {
            updateHudClock(dateEl, timeEl);
        }, 1000);
    }

    // Replace visible Fedora/Kinoite strings and logo images inside an element subtree
    function rebrandSubtree(rootNode) {
        if (!rootNode) {
            return;
        }
        if (rootNode.id === "sl-cyber-hud" || (rootNode.closest && rootNode.closest("#sl-cyber-hud"))) {
            return;
        }

        // Replace brand strings in visible text nodes
        var walker = document.createTreeWalker(rootNode, NodeFilter.SHOW_TEXT, null, false);
        var textNode;
        while ((textNode = walker.nextNode())) {
            var parent = textNode.parentElement;
            if (!parent) {
                continue;
            }
            var tag = parent.tagName;
            if (tag === "SCRIPT" || tag === "STYLE" || tag === "TEXTAREA" || parent.closest("#sl-cyber-hud")) {
                continue;
            }
            var val = textNode.nodeValue;
            if (val && /fedora|kinoite/i.test(val)) {
                var updated = val
                    .replace(/Fedora\s+Linux\s+\d+(\s*\([^)]+\))?/gi, "SourceLess OS")
                    .replace(/Fedora\s+Kinoite/gi, "SourceLess OS")
                    .replace(/Fedora\s+Linux/gi, "SourceLess OS")
                    .replace(/\bFedora\b/gi, "SourceLess OS")
                    .replace(/\bKinoite\b/gi, "SourceLess OS");
                if (updated !== val) {
                    textNode.nodeValue = updated;
                }
            }
        }

        // Swap Fedora logos or alt text in rendered image elements
        if (rootNode.querySelectorAll) {
            var imgs = rootNode.querySelectorAll("img");
            for (var i = 0; i < imgs.length; i++) {
                var img = imgs[i];
                if (img.closest && img.closest("#sl-cyber-hud")) {
                    continue;
                }
                var src = img.getAttribute("src") || "";
                var alt = img.getAttribute("alt") || "";
                if (/fedora|redhat/i.test(src) || /fedora|redhat/i.test(alt)) {
                    img.setAttribute("src", BRAND_LOGO);
                    img.setAttribute("alt", "SourceLess OS");
                }
            }
        }
    }

    function init() {
        enforceDarkClasses();
        ensureTopHud();
        rebrandSubtree(document.body || document.documentElement);

        var observer = new MutationObserver(function (mutations) {
            enforceDarkClasses();
            ensureTopHud();
            for (var i = 0; i < mutations.length; i++) {
                var m = mutations[i];
                if (m.type === "characterData") {
                    if (m.target && m.target.parentElement) {
                        rebrandSubtree(m.target.parentElement);
                    }
                } else if (m.addedNodes && m.addedNodes.length > 0) {
                    for (var j = 0; j < m.addedNodes.length; j++) {
                        var node = m.addedNodes[j];
                        if (node.nodeType === 1) {
                            rebrandSubtree(node);
                        } else if (node.nodeType === 3 && node.parentElement) {
                            rebrandSubtree(node.parentElement);
                        }
                    }
                }
            }
        });

        observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            characterData: true,
            attributes: true,
            attributeFilter: ["class"]
        });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", init);
    } else {
        init();
    }
})();
