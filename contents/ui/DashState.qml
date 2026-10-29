pragma Singleton
import QtQuick
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.private.mpris as Mpris
import "js/Utils.js" as Utils

QtObject {
    id: state

    // ------------------------------------------------------------------
    // System data
    // ------------------------------------------------------------------
    property var sys: ({
        cpu: 0, mem: 0, memUsed: 0, memTotal: 0, swap: 0, swapTotal: 0,
        disk: 0, diskUsed: 0, diskTotal: 0,
        down: 0, up: 0, uptime: 0, temp: 0, battery: -1
    })
    property var cpuHist: []
    property var netHist: []
    property var _prevCpu: null
    property var _prevNet: null
    property real _prevTime: 0

    // ------------------------------------------------------------------
    // Apps data
    // ------------------------------------------------------------------
    property var appList: []
    property var pinnedIds: []
    property var otherFavUrls: []
    property bool favsLoaded: false

    readonly property ListModel appsModel: ListModel {}

    signal requestClose()
    signal resetView()

    // shared media player model (used by Media tab + mini control)
    readonly property Mpris.Mpris2Model mpris: Mpris.Mpris2Model {}

    // static system info (os, kernel, cpu, user…)
    property var sysInfo: ({})

    // ------------------------------------------------------------------
    // Data plumbing (executable data engine)
    // ------------------------------------------------------------------
    readonly property url sysUrl: Qt.resolvedUrl("../code/sysmon.sh")
    readonly property url scanUrl: Qt.resolvedUrl("../code/scanapps.sh")
    readonly property url infoUrl: Qt.resolvedUrl("../code/sysinfo.sh")
    readonly property string sysCmd: "sh " + shUrl(sysUrl)
    readonly property string scanCmd: "sh " + shUrl(scanUrl)
    readonly property string infoCmd: "sh " + shUrl(infoUrl)
    readonly property string favsCmd:
        "kreadconfig6 --file klauncherrc --group Favorites --key FavoritesURLs 2>/dev/null; echo '---';"
        + " grep -h '^launchers=' ~/.config/plasma-org.kde.plasma.desktop-appletsrc 2>/dev/null | head -5"

    property int _seq: 0

    // configurable refresh rate (ms); wired from the widget settings
    property int refreshInterval: 1500
    onRefreshIntervalChanged: run.interval = refreshInterval

    function shUrl(u) {
        return sh(u.toString().replace(/^file:\/\//, ""));
    }

    function sh(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // one-shot execution (unique "#n" suffix so sources never collide)
    function runOnce(cmd) {
        run.connectSource(cmd + " #" + (_seq++));
    }

    readonly property P5Support.DataSource run: P5Support.DataSource {
        engine: "executable"
        interval: 1500
        onNewData: (sourceName, data) => {
            var out = data && data["stdout"] !== undefined ? String(data["stdout"]) : "";
            var base = String(sourceName).split(" #")[0];
            if (base === state.sysCmd) {
                state.parseSys(out);             // keep connected: periodic poll
                return;
            }
            if (base === state.scanCmd) {
                state.parseApps(out);
                disconnectSource(sourceName);
                return;
            }
            if (base === state.favsCmd) {
                state.parseFavs(out);
                disconnectSource(sourceName);
                return;
            }
            if (base === state.infoCmd) {
                state.parseSysInfo(out);
                disconnectSource(sourceName);
                return;
            }
            disconnectSource(sourceName);        // fire & forget (launch, pin…)
        }
    }

    function init() {
        run.connectSource(sysCmd);
        rescanApps();
        readFavorites();
        readSysInfo();
    }

    function rescanApps() {
        runOnce(scanCmd);
    }

    function readFavorites() {
        runOnce(favsCmd);
    }

    function readSysInfo() {
        runOnce(infoCmd);
    }

    function parseSysInfo(text) {
        var o = {};
        var lines = String(text).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var idx = lines[i].indexOf(":");
            if (idx < 1) { continue; }
            var k = lines[i].slice(0, idx);
            var v = lines[i].slice(idx + 1).trim();
            if (k === "FACE" && v.charAt(0) === "/") { v = "file://" + v; }
            if (k === "GPU") {
                if (!o.GPUS) { o.GPUS = []; }
                o.GPUS.push(v);
                continue;
            }
            o[k] = v;
        }
        sysInfo = o;
    }

    // ------------------------------------------------------------------
    // System parsing
    // ------------------------------------------------------------------
    function parseSys(text) {
        var cpuT = 0, cpuI = 0, memT = 0, memA = 0, swT = 0, swF = 0,
            netR = 0, netX = 0, dT = 0, dU = 0, up = 0, temp = 0, bat = -1,
            cpuTemp = 0;
        var gpuMap = {};
        var lines = String(text).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i];
            if (l.indexOf("C:") === 0) {
                var p = l.slice(2).split(":");
                cpuT = parseInt(p[0]) || 0;
                cpuI = parseInt(p[1]) || 0;
            } else if (l.indexOf("M:") === 0) {
                var m = l.slice(2).split(":");
                memT = parseInt(m[0]) || 0;
                memA = parseInt(m[1]) || 0;
                swT = parseInt(m[2]) || 0;
                swF = parseInt(m[3]) || 0;
            } else if (l.indexOf("N:") === 0) {
                var n = l.slice(2).split(":");
                netR = parseInt(n[0]) || 0;
                netX = parseInt(n[1]) || 0;
            } else if (l.indexOf("D:") === 0) {
                var d = l.slice(2).split(":");
                dT = parseInt(d[0]) || 0;
                dU = parseInt(d[1]) || 0;
            } else if (l.indexOf("U:") === 0) {
                up = parseInt(l.slice(2)) || 0;
            } else if (l.indexOf("T:") === 0) {
                temp = (parseInt(l.slice(2)) || 0) / 1000;
            } else if (l.indexOf("CT:") === 0) {
                cpuTemp = (parseInt(l.slice(3)) || 0) / 1000;
            } else if (l.indexOf("GU:") === 0) {
                var gu = l.slice(3).split(":");
                var gbusy = parseFloat(gu[1]);
                if (!gpuMap[gu[0]]) { gpuMap[gu[0]] = { busy: -1, temp: 0 }; }
                if (!isNaN(gbusy)) {
                    gpuMap[gu[0]].busy = Math.max(0, Math.min(1, gbusy / 100));
                }
            } else if (l.indexOf("GT:") === 0) {
                var gt = l.slice(3).split(":");
                var gtt = parseInt(gt[1]);
                if (!gpuMap[gt[0]]) { gpuMap[gt[0]] = { busy: -1, temp: 0 }; }
                if (!isNaN(gtt) && gtt > 0) {
                    gpuMap[gt[0]].temp = gtt / 1000;
                }
            } else if (l.indexOf("B:") === 0) {
                bat = parseInt(l.slice(2));
                if (isNaN(bat)) { bat = -1; }
            }
        }

        var gpus = [];
        for (var g in gpuMap) {
            gpus.push({ name: g, busy: gpuMap[g].busy, temp: gpuMap[g].temp });
        }
        gpus.sort(function(a, b) { return a.name.localeCompare(b.name); });

        var now = Date.now();
        var dt = _prevTime > 0 ? Math.max(0.3, (now - _prevTime) / 1000) : 1.5;

        var cpu = 0;
        if (_prevCpu !== null && cpuT > _prevCpu.t) {
            var dTot = cpuT - _prevCpu.t;
            var dIdle = cpuI - _prevCpu.i;
            if (dTot > 0) { cpu = Math.max(0, Math.min(1, 1 - dIdle / dTot)); }
        }
        _prevCpu = { t: cpuT, i: cpuI };

        var down = 0, upS = 0;
        if (_prevNet !== null && netR >= _prevNet.r) {
            down = Math.max(0, (netR - _prevNet.r) / dt / 1024);
            upS = Math.max(0, (netX - _prevNet.x) / dt / 1024);
        }
        _prevNet = { r: netR, x: netX };
        _prevTime = now;

        var memPct = memT > 0 ? Math.min(1, (memT - memA) / memT) : 0;
        var swapPct = swT > 0 ? Math.min(1, (swT - swF) / swT) : 0;
        var diskPct = dT > 0 ? Math.min(1, dU / dT) : 0;

        sys = {
            cpu: cpu, mem: memPct,
            memUsed: (memT - memA) / 1024, memTotal: memT / 1024,
            swap: swapPct, swapTotal: swT / 1024,
            disk: diskPct, diskUsed: dU / 1024, diskTotal: dT / 1024,
            down: down, up: upS, uptime: up, temp: temp, battery: bat,
            cpuTemp: cpuTemp, gpus: gpus
        };

        var ch = cpuHist.concat([cpu]);
        if (ch.length > 90) { ch = ch.slice(ch.length - 90); }
        cpuHist = ch;

        var nh = netHist.concat([{ d: down, u: upS }]);
        if (nh.length > 90) { nh = nh.slice(nh.length - 90); }
        netHist = nh;
    }

    // ------------------------------------------------------------------
    // Apps parsing & model
    // ------------------------------------------------------------------
    function parseApps(text) {
        var out = [];
        var lines = String(text).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var f = lines[i].split("\u001f");
            if (f.length < 6) { continue; }
            var icon = f[2] !== "" ? f[2] : "application-x-executable";
            if (icon.charAt(0) === "/") { icon = "file://" + icon; }
            out.push({
                id: f[0], name: f[1],
                icon: icon,
                cats: f[3], exec: f[4], path: f[5]
            });
        }
        if (out.length > 0) {
            out.sort(function(a, b) { return a.name.localeCompare(b.name); });
            // dedupe by display name (case-insensitive); the scan order follows
            // XDG precedence, so user-directory entries win over system ones —
            // same behavior as the KDE application launcher
            var seen = {};
            var deduped = [];
            for (var d = 0; d < out.length; d++) {
                var key = out[d].name.toLowerCase();
                if (seen[key]) { continue; }
                seen[key] = true;
                deduped.push(out[d]);
            }
            appList = deduped;

            // self-heal: drop pins that no longer match any installed app
            var pruned = [];
            var changed = false;
            for (var p = 0; p < pinnedIds.length; p++) {
                var found = false;
                for (var q = 0; q < deduped.length; q++) {
                    if (deduped[q].id === pinnedIds[p]) { found = true; break; }
                }
                if (found) {
                    pruned.push(pinnedIds[p]);
                } else {
                    changed = true;
                }
            }
            if (changed) {
                pinnedIds = pruned;
                writeFavorites();
            }

            rebuildApps();
        }
    }

    function rebuildApps() {
        var rows = [];
        for (var i = 0; i < appList.length; i++) {
            var a = appList[i];
            var cat = Utils.resolveCat(a.cats);
            rows.push({
                id: a.id, name: a.name, icon: a.icon,
                cat: cat.name, catIcon: cat.icon,
                pinned: pinnedIds.indexOf(a.id) >= 0,
                path: a.path
            });
        }
        appsModel.clear();
        if (rows.length > 0) { appsModel.append(rows); }
    }

    function parseFavs(text) {
        var parts = String(text).split("---");
        var kickoffLine = (parts[0] || "").trim();
        var taskbarLine = "";
        var tl = (parts[1] || "").split("\n");
        for (var i = 0; i < tl.length; i++) {
            var s = tl[i].trim();
            if (s.indexOf("launchers=") === 0 && s.length > 10) {
                taskbarLine = s.slice(10);
                break;
            }
        }

        // split favorites into app pins and other URLs (preferred:// etc.)
        var kickoffIds = [];
        var others = [];
        if (kickoffLine !== "") {
            var items = kickoffLine.split(",");
            for (var j = 0; j < items.length; j++) {
                var u = items[j].trim();
                if (u === "") { continue; }
                if (u.indexOf("applications:") === 0) {
                    var id = u.slice(13);
                    if (id !== "" && kickoffIds.indexOf(id) < 0) { kickoffIds.push(id); }
                } else {
                    others.push(u);
                }
            }
        }
        otherFavUrls = others;

        if (kickoffIds.length > 0) {
            pinnedIds = kickoffIds;
        } else if (!favsLoaded && pinnedIds.length === 0 && taskbarIds.length > 0) {
            // first-run migration from taskbar launchers only
            pinnedIds = taskbarIds;
            writeFavorites();
        }
        // never clobber existing pins with the taskbar fallback
        favsLoaded = true;
        rebuildApps();
    }

    // ------------------------------------------------------------------
    // Actions
    // ------------------------------------------------------------------
    function launch(path, id) {
        // Launch through the user systemd manager so the app is spawned by
        // systemd instead of living in plasmashell's process tree: apps
        // launched from inside plasmashell get torn down (and often crash)
        // whenever plasmashell restarts. gio handles desktop-file parsing
        // inside the transient unit; fall back to a plain gio/gtk-launch if
        // systemd-run is unavailable.
        var unit = "app-csm-" + Date.now();
        var script = shUrl(Qt.resolvedUrl("../code/launchapp.sh"));
        runOnce("systemd-run --user --collect --unit=" + unit + " -p Description='Custom Start Menu' "
              + sh(script) + " " + sh(path) + " " + sh(id)
              + " || gio launch " + sh(path) + " 2>/dev/null"
              + " || gtk-launch " + sh(id) + " 2>/dev/null");
        requestClose();
    }

    function togglePin(id) {
        var ids = pinnedIds.slice();
        var idx = ids.indexOf(id);
        if (idx >= 0) {
            ids.splice(idx, 1);
        } else {
            ids.unshift(id);
        }
        pinnedIds = ids;
        writeFavorites();
        rebuildApps();
    }

    // new order for the Pinned tab (drag & drop); persisted to klauncherrc
    function reorderPinned(ids) {
        var next = [];
        for (var i = 0; i < ids.length; i++) {
            if (pinnedIds.indexOf(ids[i]) >= 0 && next.indexOf(ids[i]) < 0) {
                next.push(ids[i]);
            }
        }
        for (var j = 0; j < pinnedIds.length; j++) {
            if (next.indexOf(pinnedIds[j]) < 0) { next.push(pinnedIds[j]); }
        }
        if (next.length === pinnedIds.length) {
            var same = true;
            for (var k = 0; k < next.length; k++) {
                if (next[k] !== pinnedIds[k]) { same = false; break; }
            }
            if (same) { return; }
        }
        pinnedIds = next;
        writeFavorites();
    }

    function writeFavorites() {
        var urls = [];
        for (var i = 0; i < otherFavUrls.length; i++) {
            urls.push(otherFavUrls[i]);
        }
        for (var j = 0; j < pinnedIds.length; j++) {
            var id = pinnedIds[j];
            if (!/\.desktop$/.test(id)) { id = id + ".desktop"; }
            urls.push("applications:" + id);
        }
        runOnce("kwriteconfig6 --file klauncherrc --group Favorites --key FavoritesURLs " + sh(urls.join(",")));
    }

    // ------------------------------------------------------------------
    // Session actions
    // ------------------------------------------------------------------
    function reboot() {
        requestClose();
        runOnce("systemctl reboot");
    }

    function powerOff() {
        requestClose();
        runOnce("systemctl poweroff");
    }

    function logOut() {
        requestClose();
        runOnce("gdbus call --session --dest org.kde.Shutdown --object-path /Shutdown --method org.kde.Shutdown.logout");
    }
}
