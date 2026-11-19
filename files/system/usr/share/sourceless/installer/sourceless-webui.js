/*
 * SourceLess OS — Anaconda WebUI Logic & Branding Controller (Fedora 45)
 * Performance-tuned (debounced childList observer, no backdrop blur):
 *  - Sets Cyber Dark classes & injects Top Cyber HUD.
 *  - Enforces English (US) default locale cleanly without overriding user picks.
 *  - Converts the open PatternFly language menu into a collapsible dropdown.
 *  - Injects Custom Disk Space Allocation controls on Installation method.
 *  - Hides Root Account / Create Account step (Windows-style First-Boot OOBE).
 */

(function () {
    "use strict";

    var HELPER_URL = "http://127.0.0.1:18443";
    var TMP_OOBE_USER = "sourceless-setup";
    var TMP_OOBE_NAME = "SourceLess Setup";
    var TMP_OOBE_PASS = "K9#mP2!vX7$qR4@w";

    var hudClockTimer = null;
    var enhanceRaf = 0;
    var enhanceDebounce = null;
    var isEnhancing = false;
    var lastStepType = "";
    var cameFromReviewBack = false;
    var cachedDiskInfo = null;
    var diskFetchInFlight = false;
    var diskLimitTimer = null;
    var accountsSkipTimer = null;
    var accountsSkipAttempts = 0;

    function applyDarkThemeClasses() {
        var html = document.documentElement;
        var body = document.body;
        if (html) {
            html.classList.add("pf-v5-theme-dark", "pf-v6-theme-dark");
        }
        if (body) {
            body.classList.add("pf-v5-theme-dark", "pf-v6-theme-dark");
        }
    }

    function updateClock() {
        var clockEl = document.getElementById("sl-hud-clock");
        var dateEl = document.getElementById("sl-hud-date");
        if (!clockEl || !dateEl) return;
        var now = new Date();
        clockEl.textContent = now.toLocaleTimeString("en-GB", {
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit"
        });
        dateEl.textContent = now.toLocaleDateString("en-US", {
            weekday: "short",
            day: "2-digit",
            month: "short",
            year: "numeric"
        });
    }

    function ensureCyberHud() {
        if (!document.body || document.getElementById("sl-cyber-hud")) return;

        var hud = document.createElement("header");
        hud.id = "sl-cyber-hud";
        hud.innerHTML =
            '<div class="sl-hud-left">' +
            '  <img class="sl-hud-logo" src="./logo.svg" alt="SourceLess OS" />' +
            '  <span class="sl-hud-brand">SourceLess OS</span>' +
            '  <span class="sl-hud-divider"></span>' +
            '  <span class="sl-hud-dot"></span>' +
            '  <span class="sl-hud-subtitle">SYSTEM INSTALLER // DEPLOYMENT</span>' +
            "</div>" +
            '<div class="sl-hud-right">' +
            '  <span id="sl-hud-date" class="sl-hud-date"></span>' +
            '  <span class="sl-hud-divider"></span>' +
            '  <span id="sl-hud-clock" class="sl-hud-clock"></span>' +
            "</div>";

        document.body.insertBefore(hud, document.body.firstChild);
        updateClock();
        if (!hudClockTimer) {
            hudClockTimer = window.setInterval(updateClock, 1000);
        }
    }

    function requestHelperDefaultsOnce() {
        if (window.sessionStorage && window.sessionStorage.getItem("sl_defaults_req") === "1") {
            return;
        }
        if (window.sessionStorage) {
            window.sessionStorage.setItem("sl_defaults_req", "1");
        }
        try {
            window.fetch(HELPER_URL + "/init-defaults", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: "{}"
            }).catch(function () {});
        } catch (_) {}
    }

    function scrubBrandingAndStagingName() {
        if (!document.body) return;

        var imgs = document.querySelectorAll('img[src*="fedora" i], img[alt*="fedora" i]');
        for (var i = 0; i < imgs.length; i++) {
            if (imgs[i].getAttribute("data-sl-logo") !== "1") {
                imgs[i].src = "./logo.svg";
                imgs[i].alt = "SourceLess OS";
                imgs[i].setAttribute("data-sl-logo", "1");
            }
        }

        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
            acceptNode: function (node) {
                var parent = node.parentElement;
                if (!parent) return NodeFilter.FILTER_REJECT;
                var tag = parent.tagName;
                if (tag === "SCRIPT" || tag === "STYLE" || tag === "TEXTAREA" || tag === "INPUT") {
                    return NodeFilter.FILTER_REJECT;
                }
                if (parent.closest && parent.closest("#sl-cyber-hud")) {
                    return NodeFilter.FILTER_REJECT;
                }
                if (/(fedora|kinoite|sourceless-setup|sourceless setup)/i.test(node.nodeValue || "")) {
                    return NodeFilter.FILTER_ACCEPT;
                }
                return NodeFilter.FILTER_REJECT;
            }
        });

        var targets = [];
        while (walker.nextNode()) {
            targets.push(walker.currentNode);
        }

        for (var j = 0; j < targets.length; j++) {
            var val = targets[j].nodeValue;
            var updated = val
                .replace(/Fedora\s+Linux\s+Kinoite/gi, "SourceLess OS")
                .replace(/Fedora\s+Kinoite/gi, "SourceLess OS")
                .replace(/Fedora\s+Linux/gi, "SourceLess OS")
                .replace(/\bFedora\b/gi, "SourceLess OS")
                .replace(/\bKinoite\b/gi, "SourceLess OS")
                .replace(/sourceless-setup/gi, "First-Boot Setup (Windows-style OOBE)")
                .replace(/SourceLess Setup/gi, "First-Boot Setup (Windows-style OOBE)");
            if (updated !== val) {
                targets[j].nodeValue = updated;
            }
        }
    }

    function removeUpstreamSubheader() {
        var candidates = document.querySelectorAll(
            "header, .pf-v6-c-page__header, .pf-v5-c-page__header, .pf-v6-c-masthead, .pf-v5-c-masthead, " +
            ".pf-v6-c-page__main-section, .pf-v5-c-page__main-section, .pf-v6-c-page__main-group, [class*='header' i]"
        );

        for (var i = 0; i < candidates.length; i++) {
            var el = candidates[i];
            if (!el || el.id === "sl-cyber-hud") continue;
            if (el.closest && el.closest("#sl-cyber-hud")) continue;
            if (el.querySelector && (el.querySelector(".pf-v6-c-wizard, .pf-v5-c-wizard") || el.querySelector("#sl-cyber-hud"))) {
                continue;
            }
            if (el.closest && el.closest(".pf-v6-c-wizard, .pf-v5-c-wizard")) continue;

            var isShellHeader = el.matches(
                "header, .pf-v6-c-page__header, .pf-v5-c-page__header, .pf-v6-c-masthead, .pf-v5-c-masthead"
            );
            var text = (el.textContent || "").trim().replace(/\s+/g, " ");
            var isTitleBanner = text.length > 0 && text.length < 140 &&
                /((sourceless os|fedora)\s+(installation|installer)|instalare\s+sourceless)/i.test(text);

            if (isShellHeader || isTitleBanner) {
                el.classList.add("sl-removed-subheader");
                var sec = el.closest(".pf-v6-c-page__main-section, .pf-v5-c-page__main-section, .pf-v6-c-page__main-group");
                if (sec && !sec.querySelector(".pf-v6-c-wizard, .pf-v5-c-wizard") && !sec.querySelector("#sl-cyber-hud")) {
                    sec.classList.add("sl-removed-subheader");
                }
            }
        }

        // Catch standalone banner headings rendered outside the wizard card
        var headings = document.querySelectorAll("h1, .pf-v6-c-title, .pf-v5-c-title");
        for (var h = 0; h < headings.length; h++) {
            var hd = headings[h];
            if (hd.closest && (hd.closest(".pf-v6-c-wizard, .pf-v5-c-wizard") || hd.closest("#sl-cyber-hud"))) {
                continue;
            }
            var hTxt = (hd.textContent || "").trim();
            if (/((sourceless os|fedora)\s+(installation|installer)|instalare\s+sourceless)/i.test(hTxt)) {
                var box = hd.closest(".pf-v6-c-page__main-section, .pf-v5-c-page__main-section, .pf-v6-c-page__main-group, header, div");
                if (box && !box.querySelector(".pf-v6-c-wizard, .pf-v5-c-wizard") && !box.querySelector("#sl-cyber-hud")) {
                    box.classList.add("sl-removed-subheader");
                }
            }
        }
    }

    function getActiveWizardStepKey() {
        var current = document.querySelector(
            ".pf-v6-c-wizard__nav-link.pf-m-current, .pf-v5-c-wizard__nav-link.pf-m-current"
        );
        if (!current) return "";
        var text = (current.textContent || "").toLowerCase();
        var id = (current.id || "").toLowerCase();
        var combo = text + " " + id;

        if (/welcome|bine a[tț]i venit|language|anaconda-screen-welcome/.test(combo)) return "welcome";
        if (/installation method|metoda de instalare|installation-method/.test(combo)) return "method";
        if (/create account|creeaz[aă] cont|accounts/.test(combo)) return "accounts";
        if (/review and install|revizui[tț]i|summary/.test(combo)) return "review";
        if (/storage configuration|configurare stocare/.test(combo)) return "storage";
        return text.trim();
    }

    function syncWizardMainClasses(stepKey) {
        var mainBody = document.querySelector(".pf-v6-c-wizard__main-body, .pf-v5-c-wizard__main-body");
        if (!mainBody) return;
        mainBody.classList.toggle("sl-welcome-page", stepKey === "welcome");
    }

    function hideAccountStepperAndRoot() {
        var navLinks = document.querySelectorAll(".pf-v6-c-wizard__nav-link, .pf-v5-c-wizard__nav-link");
        for (var i = 0; i < navLinks.length; i++) {
            var link = navLinks[i];
            var combo = ((link.textContent || "") + " " + (link.id || "")).toLowerCase();
            if (/create account|creeaz[aă] cont|accounts/.test(combo)) {
                var item = link.closest(".pf-v6-c-wizard__nav-item, .pf-v5-c-wizard__nav-item, li") || link;
                item.classList.add("sl-hidden-step");
            }
        }

        // Hide any Root Account / Enable Root Access controls on screen
        var rootCandidates = document.querySelectorAll(
            "h2, h3, h4, .pf-v6-c-form__section-title, legend, label, .pf-v6-c-check__label, .pf-v5-c-check__label, .pf-v6-c-form__label-text"
        );
        for (var j = 0; j < rootCandidates.length; j++) {
            var node = rootCandidates[j];
            if (node.closest && node.closest("#sl-cyber-hud")) continue;
            var txt = (node.textContent || "").toLowerCase();
            if (/\b(enable\s+root|root\s*(account|access|password|user)|cont\s*root|acces\s*root|ssh\s*root)\b/.test(txt)) {
                var sec = node.closest(
                    ".pf-v6-c-check, .pf-v5-c-check, .pf-v6-c-form__group, .pf-v5-c-form__group, " +
                    ".pf-v6-c-switch, .pf-v6-c-expandable-section, section, .pf-v6-c-form__section, .pf-v6-c-card, fieldset"
                );
                if (sec) {
                    var cbs = sec.querySelectorAll('input[type="checkbox"]');
                    for (var k = 0; k < cbs.length; k++) {
                        if (cbs[k].checked) cbs[k].click();
                    }
                    sec.classList.add("sl-hidden-root");
                }
            }
        }
    }

    /* =========================================================
     * Welcome Page: En (US) auto-selection & Collapsible Dropdown
     * ========================================================= */
    function getSelectedLanguageLabel(menuEl) {
        if (!menuEl) return "English (United States)";
        var selected = menuEl.querySelector(
            '.pf-v6-c-menu__item.pf-m-selected, .pf-v5-c-menu__item.pf-m-selected, [aria-current="true"], [aria-selected="true"]'
        );
        if (!selected) {
            var checkedIcon = menuEl.querySelector(".pf-v6-c-menu__item-select-icon, .pf-v5-c-menu__item-select-icon");
            if (checkedIcon) {
                selected = checkedIcon.closest("button, li, .pf-v6-c-menu__item, .pf-v5-c-menu__item");
            }
        }
        if (selected) {
            var raw = (selected.textContent || "").trim().replace(/\s+/g, " ");
            if (raw) return raw;
        }
        return "English (United States)";
    }

    function enhanceWelcomeLanguageDropdown(stepKey) {
        if (stepKey !== "welcome") return;
        var mainBody = document.querySelector(".pf-v6-c-wizard__main-body, .pf-v5-c-wizard__main-body");
        if (!mainBody) return;

        var langMenu = mainBody.querySelector(
            ".pf-v6-c-menu.pf-m-scrollable, .pf-v5-c-menu.pf-m-scrollable, [class*='c-menu'][class*='m-scrollable']"
        );
        if (!langMenu) return;

        var host = langMenu.parentElement;
        if (!host) return;
        host.classList.add("sl-lang-host");

        // Auto-select English (United States) once at startup unless user explicitly picked another language
        var userPicked = window.sessionStorage && window.sessionStorage.getItem("sl_user_picked_lang") === "1";
        var enApplied = window.sessionStorage && window.sessionStorage.getItem("sl_en_default_set") === "1";
        var currentLabel = getSelectedLanguageLabel(langMenu);

        if (!userPicked && !enApplied && currentLabel.toLowerCase().indexOf("english (united states)") === -1) {
            var options = langMenu.querySelectorAll("button, [role='menuitem'], [role='menuitemradio'], [role='option']");
            for (var i = 0; i < options.length; i++) {
                var txt = (options[i].textContent || "").trim().toLowerCase();
                if (txt.indexOf("english (united states)") !== -1 || txt === "english (us)") {
                    if (window.sessionStorage) {
                        window.sessionStorage.setItem("sl_en_default_set", "1");
                    }
                    options[i].click();
                    currentLabel = (options[i].textContent || "").trim();
                    break;
                }
            }
        }

        // Inject collapsible trigger button once inside host (without moving React nodes)
        var trigger = host.querySelector(":scope > .sl-lang-trigger");
        if (!trigger) {
            trigger = document.createElement("button");
            trigger.type = "button";
            trigger.className = "sl-lang-trigger";
            trigger.innerHTML =
                '<span class="sl-lang-trigger-left">' +
                '  <span class="sl-lang-badge"></span>' +
                '  <span class="sl-lang-label"></span>' +
                "</span>" +
                '<span class="sl-lang-chevron">&#9662;</span>';

            trigger.addEventListener("click", function (ev) {
                ev.preventDefault();
                ev.stopPropagation();
                var willOpen = !host.classList.contains("sl-lang-open");
                host.classList.toggle("sl-lang-open", willOpen);
                if (willOpen) {
                    var searchInput = host.querySelector("input[type='search'], input[type='text']");
                    if (searchInput) {
                        window.setTimeout(function () {
                            searchInput.focus();
                        }, 30);
                    }
                }
            });

            host.insertBefore(trigger, host.firstChild);

            if (langMenu.dataset.slMenuBound !== "1") {
                langMenu.dataset.slMenuBound = "1";
                langMenu.addEventListener("click", function (ev) {
                    var clickedItem = ev.target.closest(
                        "button, [role='menuitem'], [role='menuitemradio'], [role='option'], .pf-v6-c-menu__item, .pf-v5-c-menu__item"
                    );
                    if (!clickedItem) return;
                    if (ev.isTrusted && window.sessionStorage) {
                        window.sessionStorage.setItem("sl_user_picked_lang", "1");
                    }
                    window.setTimeout(function () {
                        host.classList.remove("sl-lang-open");
                        var lbl = host.querySelector(".sl-lang-label");
                        if (lbl) lbl.textContent = getSelectedLanguageLabel(langMenu);
                    }, 90);
                });
            }
        }

        var labelSpan = trigger.querySelector(".sl-lang-label");
        if (labelSpan) {
            labelSpan.textContent = currentLabel;
        }
    }

    /* =========================================================
     * Installation Method: Custom Disk Space Allocation Card
     * ========================================================= */
    function parseDiskGiBFromDom(mainBody) {
        var text = (mainBody && mainBody.textContent) || "";
        var m = text.match(/(\d+(?:[.,]\d+)?)\s*(GiB|GB|TB|TiB)/i);
        if (!m) return { name: "System Disk", gib: 48 };
        var num = parseFloat(m[1].replace(",", "."));
        var unit = m[2].toUpperCase();
        if (unit === "TB" || unit === "TIB") num = num * 1024;
        else if (unit === "GB") num = Math.round((num * 1000 / 1024) * 10) / 10;
        var devMatch = text.match(/\((nvme\d+n\d+|sd[a-z]+|vd[a-z]+|hd[a-z]+)\)/i);
        return {
            name: devMatch ? devMatch[1] : "Selected Disk",
            gib: Math.max(20, Math.round(num))
        };
    }

    function pickBestDiskInfo(mainBody) {
        var domHint = parseDiskGiBFromDom(mainBody);
        if (!cachedDiskInfo || !cachedDiskInfo.disks || !cachedDiskInfo.disks.length) {
            return { name: domHint.name, gib: domHint.gib, limit: null };
        }
        var selected = null;
        for (var i = 0; i < cachedDiskInfo.disks.length; i++) {
            var d = cachedDiskInfo.disks[i];
            if (domHint.name && d.name === domHint.name) {
                selected = d;
                break;
            }
        }
        if (!selected) {
            selected = cachedDiskInfo.disks[0];
            for (var j = 1; j < cachedDiskInfo.disks.length; j++) {
                if (cachedDiskInfo.disks[j].size_gib > selected.size_gib) {
                    selected = cachedDiskInfo.disks[j];
                }
            }
        }
        return {
            name: selected.name,
            gib: Math.max(16, Math.round(selected.size_gib)),
            limit: cachedDiskInfo.limit_gib
        };
    }

    function sendDiskLimit(limitGib) {
        if (diskLimitTimer) window.clearTimeout(diskLimitTimer);
        diskLimitTimer = window.setTimeout(function () {
            window.fetch(HELPER_URL + "/set-disk-limit", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ limit_gib: limitGib })
            }).catch(function () {});
        }, 120);
    }

    function fetchDiskInfoAndUpdateCard() {
        if (diskFetchInFlight) return;
        diskFetchInFlight = true;
        window.fetch(HELPER_URL + "/disk-info", { method: "GET" })
            .then(function (resp) { return resp.json(); })
            .then(function (data) {
                cachedDiskInfo = data;
                diskFetchInFlight = false;
                enhanceInstallMethodDiskCard(getActiveWizardStepKey());
            })
            .catch(function () {
                diskFetchInFlight = false;
            });
    }

    function syncDiskCardNumbers(totalGib, allocGib, modeOverride) {
        var minGib = Math.min(16, totalGib);
        var clamped = Math.min(totalGib, Math.max(minGib, Math.round(allocGib)));
        var remaining = Math.max(0, totalGib - clamped);
        var pct = totalGib > 0 ? Math.min(100, Math.round((clamped / totalGib) * 100)) : 100;
        var mode = modeOverride || (clamped >= totalGib ? "full" : "custom");

        var fullRadio = document.querySelector('#sl-disk-allocation-card input[value="full"]');
        var customRadio = document.querySelector('#sl-disk-allocation-card input[value="custom"]');
        if (fullRadio && customRadio) {
            fullRadio.checked = (mode === "full");
            customRadio.checked = (mode === "custom");
        }

        var slider = document.getElementById("sl-disk-slider");
        var input = document.getElementById("sl-disk-gib-input");
        var fill = document.getElementById("sl-disk-bar-fill");
        var allocText = document.getElementById("sl-disk-alloc-text");
        var freeText = document.getElementById("sl-disk-free-text");

        if (slider) slider.value = String(clamped);
        if (input) input.value = String(clamped);
        if (fill) fill.style.width = pct + "%";
        if (allocText) allocText.textContent = clamped + " GiB (" + pct + "%)";
        if (freeText) freeText.textContent = remaining + " GiB";

        var presetBtns = document.querySelectorAll("#sl-disk-allocation-card .sl-preset-btn");
        for (var b = 0; b < presetBtns.length; b++) {
            var pVal = parseInt(presetBtns[b].getAttribute("data-pct"), 10);
            var targetForPreset = pVal === 100 ? totalGib : Math.min(totalGib, Math.max(minGib, Math.round((totalGib * pVal) / 100)));
            presetBtns[b].classList.toggle("sl-active", clamped === targetForPreset);
        }

        return clamped;
    }

    function findUseEntireDiskWrapper(mainBody) {
        var radios = mainBody.querySelectorAll('input[type="radio"]');
        for (var i = 0; i < radios.length; i++) {
            if (radios[i].closest("#sl-disk-allocation-card")) continue;
            var wrap = radios[i].closest(".pf-v6-c-radio, .pf-v5-c-radio, label, div");
            var txt = ((wrap && wrap.textContent) || "").toLowerCase();
            if (/use entire disk|folose[sș]te întregul disc|entire disk/.test(txt)) {
                return { radio: radios[i], wrap: wrap };
            }
        }
        return null;
    }

    function enhanceInstallMethodDiskCard(stepKey) {
        var existing = document.getElementById("sl-disk-allocation-card");
        if (stepKey !== "method") {
            if (existing) existing.remove();
            return;
        }

        var mainBody = document.querySelector(".pf-v6-c-wizard__main-body, .pf-v5-c-wizard__main-body");
        if (!mainBody) return;

        if (!cachedDiskInfo && !diskFetchInFlight) {
            fetchDiskInfoAndUpdateCard();
        }

        // Wait until React has rendered Destination + "Use entire disk" radio so we replace it in exact slot
        var entireTarget = findUseEntireDiskWrapper(mainBody);
        if (!entireTarget || !entireTarget.wrap || !entireTarget.wrap.parentNode) {
            return;
        }

        if (!entireTarget.radio.checked) {
            entireTarget.radio.click();
        }
        entireTarget.wrap.classList.add("sl-replaced-entire-disk");

        var disk = pickBestDiskInfo(mainBody);
        var totalGib = disk.gib;
        var minGib = Math.min(16, totalGib);
        var initialAlloc = disk.limit && disk.limit < totalGib ? disk.limit : totalGib;
        var initialMode = disk.limit && disk.limit < totalGib ? "custom" : "full";

        if (existing) {
            if (existing.previousElementSibling !== entireTarget.wrap) {
                entireTarget.wrap.parentNode.insertBefore(existing, entireTarget.wrap.nextSibling);
            }
            var badge = document.getElementById("sl-disk-badge");
            if (badge) badge.textContent = disk.name + " (" + totalGib + " GiB)";
            var sliderEl = document.getElementById("sl-disk-slider");
            if (sliderEl) {
                sliderEl.min = String(minGib);
                sliderEl.max = String(totalGib);
            }
            var inputEl = document.getElementById("sl-disk-gib-input");
            if (inputEl) {
                inputEl.min = String(minGib);
                inputEl.max = String(totalGib);
            }
            return;
        }

        var card = document.createElement("div");
        card.id = "sl-disk-allocation-card";
        card.innerHTML =
            '<div class="sl-disk-header">' +
            '  <span class="sl-disk-title">Disk Space Allocation (No Storage Editor Needed)</span>' +
            '  <span id="sl-disk-badge" class="sl-disk-badge">' + disk.name + " (" + totalGib + ' GiB)</span>' +
            "</div>" +
            '<div class="sl-disk-modes">' +
            '  <label class="sl-disk-radio-row">' +
            '    <input type="radio" name="sl-disk-mode" value="full" ' + (initialMode === "full" ? "checked" : "") + " />" +
            '    <span>Use 100% of disk (Full Capacity)</span>' +
            "  </label>" +
            '  <label class="sl-disk-radio-row">' +
            '    <input type="radio" name="sl-disk-mode" value="custom" ' + (initialMode === "custom" ? "checked" : "") + " />" +
            '    <span>Select custom disk space to use (leave remaining space unallocated)</span>' +
            "  </label>" +
            "</div>" +
            '<div id="sl-disk-custom-controls" style="display:flex">' +
            '  <div class="sl-disk-slider-row">' +
            '    <input id="sl-disk-slider" type="range" min="' + minGib + '" max="' + totalGib + '" step="1" value="' + initialAlloc + '" />' +
            '    <div class="sl-disk-number-wrap">' +
            '      <input id="sl-disk-gib-input" type="number" min="' + minGib + '" max="' + totalGib + '" value="' + initialAlloc + '" />' +
            "      <span>GiB</span>" +
            "    </div>" +
            "  </div>" +
            '  <div class="sl-disk-presets">' +
            '    <button type="button" class="sl-preset-btn" data-pct="25">25%</button>' +
            '    <button type="button" class="sl-preset-btn" data-pct="50">50%</button>' +
            '    <button type="button" class="sl-preset-btn" data-pct="75">75%</button>' +
            '    <button type="button" class="sl-preset-btn" data-pct="100">100%</button>' +
            "  </div>" +
            '  <div class="sl-disk-bar"><div id="sl-disk-bar-fill" class="sl-disk-bar-fill"></div></div>' +
            '  <div class="sl-disk-summary">' +
            '    <span>SourceLess OS: <strong id="sl-disk-alloc-text"></strong></span>' +
            '    <span>Unallocated Free Space: <strong id="sl-disk-free-text"></strong></span>' +
            "  </div>" +
            "</div>";

        entireTarget.wrap.parentNode.insertBefore(card, entireTarget.wrap.nextSibling);
        syncDiskCardNumbers(totalGib, initialAlloc, initialMode);

        var radios = card.querySelectorAll('input[name="sl-disk-mode"]');
        var slider = document.getElementById("sl-disk-slider");
        var numInput = document.getElementById("sl-disk-gib-input");

        for (var r = 0; r < radios.length; r++) {
            radios[r].addEventListener("change", function () {
                var currentDisk = pickBestDiskInfo(mainBody);
                var maxG = currentDisk.gib;
                if (this.value === "full" && this.checked) {
                    syncDiskCardNumbers(maxG, maxG, "full");
                    sendDiskLimit(null);
                } else if (this.value === "custom" && this.checked) {
                    var curVal = parseFloat(slider.value) || maxG;
                    var defaultCustom = curVal < maxG ? curVal : Math.max(Math.min(16, maxG), Math.round(maxG * 0.5));
                    var applied = syncDiskCardNumbers(maxG, defaultCustom, "custom");
                    sendDiskLimit(applied >= maxG ? null : applied);
                }
            });
        }

        slider.addEventListener("input", function () {
            var maxG = pickBestDiskInfo(mainBody).gib;
            var rawVal = parseFloat(this.value);
            var val = syncDiskCardNumbers(maxG, rawVal, rawVal >= maxG ? "full" : "custom");
            sendDiskLimit(val >= maxG ? null : val);
        });

        numInput.addEventListener("change", function () {
            var maxG = pickBestDiskInfo(mainBody).gib;
            var rawVal = parseFloat(this.value) || maxG;
            var val = syncDiskCardNumbers(maxG, rawVal, rawVal >= maxG ? "full" : "custom");
            sendDiskLimit(val >= maxG ? null : val);
        });

        var presetBtns = card.querySelectorAll(".sl-preset-btn");
        for (var p = 0; p < presetBtns.length; p++) {
            presetBtns[p].addEventListener("click", function () {
                var pct = parseInt(this.getAttribute("data-pct"), 10) || 100;
                var maxG = pickBestDiskInfo(mainBody).gib;
                var target = pct === 100 ? maxG : Math.round((maxG * pct) / 100);
                var val = syncDiskCardNumbers(maxG, target, pct === 100 ? "full" : "custom");
                sendDiskLimit(val >= maxG ? null : val);
            });
        }
    }

    /* =========================================================
     * Skip Create Account -> Windows-Style First-Boot OOBE
     * ========================================================= */
    function setReactInputValue(inputEl, val) {
        if (!inputEl) return;
        var descriptor = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value");
        if (descriptor && descriptor.set) {
            descriptor.set.call(inputEl, val);
        } else {
            inputEl.value = val;
        }
        inputEl.dispatchEvent(new Event("input", { bubbles: true }));
        inputEl.dispatchEvent(new Event("change", { bubbles: true }));
    }

    function setReactCheckboxValue(cbEl, checked) {
        if (!cbEl || cbEl.checked === checked) return;
        cbEl.click();
    }

    function findFooterButton(kind) {
        var footer = document.querySelector(".pf-v6-c-wizard__footer, .pf-v5-c-wizard__footer");
        if (!footer) return null;
        if (kind === "next") {
            return footer.querySelector("button.pf-m-primary");
        }
        var btns = footer.querySelectorAll("button");
        for (var i = 0; i < btns.length; i++) {
            var t = (btns[i].textContent || "").trim().toLowerCase();
            if (/back|înapoi/.test(t) && !btns[i].classList.contains("pf-m-primary")) {
                return btns[i];
            }
        }
        return null;
    }

    function clearAccountsSkipState() {
        if (accountsSkipTimer) {
            window.clearInterval(accountsSkipTimer);
            accountsSkipTimer = null;
        }
        accountsSkipAttempts = 0;
        var mainBody = document.querySelector(".pf-v6-c-wizard__main-body, .pf-v5-c-wizard__main-body");
        if (mainBody) mainBody.classList.remove("sl-skipping-accounts");
        var overlay = document.getElementById("sl-skip-overlay");
        if (overlay) overlay.remove();
    }

    function ensureSkipOverlay(mainBody) {
        if (!mainBody) return;
        mainBody.classList.add("sl-skipping-accounts");
        if (!document.getElementById("sl-skip-overlay")) {
            var ov = document.createElement("div");
            ov.id = "sl-skip-overlay";
            ov.innerHTML =
                '<div class="sl-skip-spinner"></div>' +
                "<div>Preparing installation summary...</div>";
            mainBody.insertBefore(ov, mainBody.firstChild);
        }
    }

    function performAccountSkipTick() {
        if (getActiveWizardStepKey() !== "accounts") {
            clearAccountsSkipState();
            return;
        }

        accountsSkipAttempts += 1;
        if (accountsSkipAttempts >= 50) {
            if (accountsSkipTimer) {
                window.clearInterval(accountsSkipTimer);
                accountsSkipTimer = null;
            }
            return;
        }

        var mainBody = document.querySelector(".pf-v6-c-wizard__main-body, .pf-v5-c-wizard__main-body");
        if (!mainBody) return;
        ensureSkipOverlay(mainBody);
        hideAccountStepperAndRoot();

        if (cameFromReviewBack) {
            var backBtn = findFooterButton("back");
            if (backBtn && !backBtn.disabled) {
                cameFromReviewBack = false;
                backBtn.click();
            }
            return;
        }

        var inputs = mainBody.querySelectorAll("input");
        var textInputs = [];
        var passInputs = [];

        for (var i = 0; i < inputs.length; i++) {
            var inp = inputs[i];
            if (inp.type === "checkbox") {
                var lbl = ((inp.closest(".pf-v6-c-check, .pf-v5-c-check, label, .pf-v6-c-form__group, .pf-v5-c-form__group") || {}).textContent || "").toLowerCase();
                if (/root|skip\s*user|no\s*user|admin|sudo|wheel/.test(lbl)) {
                    setReactCheckboxValue(inp, false);
                } else if (/require\s*password|use\s*password|create\s*(user|account)|parol[aă]/.test(lbl)) {
                    setReactCheckboxValue(inp, true);
                }
            } else if (!inp.closest(".sl-hidden-root")) {
                if (inp.type === "password") {
                    passInputs.push(inp);
                } else if (inp.type === "text" || !inp.type) {
                    textInputs.push(inp);
                }
            }
        }

        if (textInputs.length >= 2) {
            if (textInputs[0].value !== TMP_OOBE_NAME) setReactInputValue(textInputs[0], TMP_OOBE_NAME);
            if (textInputs[1].value !== TMP_OOBE_USER) setReactInputValue(textInputs[1], TMP_OOBE_USER);
        } else if (textInputs.length === 1 && textInputs[0].value !== TMP_OOBE_USER) {
            setReactInputValue(textInputs[0], TMP_OOBE_USER);
        }

        for (var p = 0; p < passInputs.length; p++) {
            if (passInputs[p].value !== TMP_OOBE_PASS) {
                setReactInputValue(passInputs[p], TMP_OOBE_PASS);
            }
        }

        var nextBtn = findFooterButton("next");
        if (nextBtn && !nextBtn.disabled) {
            nextBtn.click();
        }
    }

    function handleCreateAccountAutoSkip(stepKey) {
        if (stepKey !== "accounts") {
            clearAccountsSkipState();
            return;
        }

        var mainBody = document.querySelector(".pf-v6-c-wizard__main-body, .pf-v5-c-wizard__main-body");
        if (mainBody) ensureSkipOverlay(mainBody);

        performAccountSkipTick();
        if (!accountsSkipTimer) {
            accountsSkipTimer = window.setInterval(performAccountSkipTick, 150);
        }
    }

    /* =========================================================
     * Main Debounced UI Enhancement Cycle
     * ========================================================= */
    function runEnhancements() {
        if (isEnhancing) return;
        isEnhancing = true;
        try {
            applyDarkThemeClasses();
            ensureCyberHud();
            removeUpstreamSubheader();
            requestHelperDefaultsOnce();

            var stepKey = getActiveWizardStepKey();
            if (stepKey !== lastStepType) {
                cameFromReviewBack = (lastStepType === "review" && stepKey === "accounts");
                lastStepType = stepKey;
            }

            syncWizardMainClasses(stepKey);
            hideAccountStepperAndRoot();
            scrubBrandingAndStagingName();
            enhanceWelcomeLanguageDropdown(stepKey);
            enhanceInstallMethodDiskCard(stepKey);
            handleCreateAccountAutoSkip(stepKey);
        } finally {
            isEnhancing = false;
        }
    }

    function scheduleEnhancements() {
        if (enhanceDebounce) return;
        enhanceDebounce = window.setTimeout(function () {
            enhanceDebounce = null;
            if (enhanceRaf) window.cancelAnimationFrame(enhanceRaf);
            enhanceRaf = window.requestAnimationFrame(runEnhancements);
        }, 80);
    }

    function bindGlobalClickListeners() {
        document.addEventListener("click", function (ev) {
            // Close open language dropdown on outside click
            var openHosts = document.querySelectorAll(".sl-lang-host.sl-lang-open");
            for (var i = 0; i < openHosts.length; i++) {
                if (!openHosts[i].contains(ev.target)) {
                    openHosts[i].classList.remove("sl-lang-open");
                }
            }

            // Track explicit Back click on Review step
            var btn = ev.target.closest("button");
            if (btn && getActiveWizardStepKey() === "review") {
                var txt = (btn.textContent || "").toLowerCase();
                if (/back|înapoi/.test(txt) && !btn.classList.contains("pf-m-primary")) {
                    cameFromReviewBack = true;
                }
            }
        });
    }

    function boot() {
        applyDarkThemeClasses();
        ensureCyberHud();
        bindGlobalClickListeners();
        runEnhancements();

        var observer = new MutationObserver(function (mutations) {
            for (var i = 0; i < mutations.length; i++) {
                var target = mutations[i].target;
                if (
                    target &&
                    target.closest &&
                    (target.closest("#sl-cyber-hud") || target.closest("#sl-disk-allocation-card") || target.closest("#sl-skip-overlay"))
                ) {
                    continue;
                }
                scheduleEnhancements();
                break;
            }
        });

        observer.observe(document.documentElement || document.body, {
            childList: true,
            subtree: true
        });
    }

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", boot);
    } else {
        boot();
    }
})();
