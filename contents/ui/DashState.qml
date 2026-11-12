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
    // Phone (KDE Connect)
    // ------------------------------------------------------------------
    property var phoneDevices: []            // [{id, name, reachable}]
    property string phoneId: ""              // selected device id
    property int phoneBattery: -1
    property bool phoneCharging: false
    property int phoneSignal: -1             // cellular strength 0-4, -1 unknown
    property string phoneNetType: ""         // "LTE", "5G", …
    property var phoneNotifs: []             // [{id, app, title, dismissable}]
    property var phoneCommands: []           // [{id, name}] registered on the phone
    property string _phoneSrc: ""            // connected poll source name
    property string _phoneNotifSrc: ""       // one-shot notifications source
    property string _phoneCmdSrc: ""         // one-shot commands source
    property int _phoneEpoch: 0              // invalidates deferred poll changes

    readonly property url phoneUrl: Qt.resolvedUrl("../code/phone.sh")

    // start/refresh the periodic phone poll (devices + battery + media)
    // NOTE: the connect/disconnect is deferred via Qt.callLater — this is
    // sometimes invoked from inside the engine's onNewData callback, and
    // touching source lifetimes there crashes plasmashell (SIGSEGV in
    // DataContainer::checkForUpdate).
    function refreshPhone() {
        var e = ++_phoneEpoch;
        Qt.callLater(function() {
            if (e !== _phoneEpoch) { return; }   // superseded or closed meanwhile
            closePhonePoll();
            var src = "sh " + shUrl(phoneUrl) + " poll " + sh(phoneId);
            _phoneSrc = src;
            phoneRun.connectSource(src);
        });
    }

    // stop the poll (popup closed / left the phone panel)
    function closePhonePoll() {
        _phoneEpoch++;                           // cancel any deferred refresh
        if (_phoneSrc !== "") {
            phoneRun.disconnectSource(_phoneSrc);
            _phoneSrc = "";
        }
    }

    // fire-and-forget phone actions ("ring", "cursor <dx> <dy>", "share <arg>"…)
    function phoneAction(action, arg, arg2) {
        if (action === "refresh") {
            runOnce("sh " + shUrl(phoneUrl) + " refresh");
            return;
        }
        if (phoneId === "") { return; }
        var cmd = "sh " + shUrl(phoneUrl) + " " + action + " " + sh(phoneId);
        if (arg !== undefined && arg !== null && String(arg) !== "") {
            cmd += " " + sh(String(arg));
        }
        if (arg2 !== undefined && arg2 !== null && String(arg2) !== "") {
            cmd += " " + sh(String(arg2));
        }
        runOnce(cmd);
    }

    function parsePhone(text) {
        var parts = String(text).split("---");

        // --- devices ---
        var devs = [];
        var dl = (parts[0] || "").split("\n");
        for (var i = 0; i < dl.length; i++) {
            var f = dl[i].split("\u001f");
            if (f.length >= 3 && f[0] !== "") {
                devs.push({ id: f[0], name: f[1], reachable: f[2] === "1" });
            }
        }
        phoneDevices = devs;

        // validate the selection; fall back to first reachable, then first
        var sel = null;
        for (var d = 0; d < devs.length; d++) {
            if (devs[d].id === phoneId) { sel = devs[d]; break; }
        }
        if (!sel && devs.length > 0) {
            for (var r = 0; r < devs.length; r++) {
                if (devs[r].reachable) { sel = devs[r]; break; }
            }
            if (!sel) { sel = devs[0]; }
        }
        if (sel && sel.id !== phoneId) {
            phoneId = sel.id;
            refreshPhone();   // re-point battery/connectivity polling at this device
            return;
        }

        // --- battery ---
        var bl = (parts[1] || "").trim().split("\u001f");
        var b = parseInt(bl[0]);
        phoneBattery = isNaN(b) ? -1 : b;
        phoneCharging = (bl[1] === "true");

        // --- connectivity ---
        var cl = (parts[2] || "").trim().split("\u001f");
        var s = parseInt(cl[0]);
        phoneSignal = isNaN(s) ? -1 : s;
        phoneNetType = cl[1] || "";
    }

    // fetch the phone's notifications (one-shot, refreshed on demand)
    function fetchPhoneNotifs() {
        closePhoneNotifs();
        if (phoneId === "") { return; }
        _phoneNotifSrc = "sh " + shUrl(phoneUrl) + " notif " + sh(phoneId);
        run.connectSource(_phoneNotifSrc);
    }

    function closePhoneNotifs() {
        if (_phoneNotifSrc !== "") {
            run.disconnectSource(_phoneNotifSrc);
            _phoneNotifSrc = "";
        }
    }

    // pick a different paired device from the panel header
    function selectPhone(id) {
        if (id === undefined || id === null || String(id) === "" || id === phoneId) {
            return;
        }
        phoneId = String(id);
        closePhoneCommands();
        refreshPhone();
    }

    // fetch the phone's registered "Run commands" entries (one-shot)
    function fetchPhoneCommands() {
        closePhoneCommands();
        if (phoneId === "") { return; }
        _phoneCmdSrc = "sh " + shUrl(phoneUrl) + " commands " + sh(phoneId);
        run.connectSource(_phoneCmdSrc);
    }

    function closePhoneCommands() {
        if (_phoneCmdSrc !== "") {
            run.disconnectSource(_phoneCmdSrc);
            _phoneCmdSrc = "";
        }
    }

    function parsePhoneCommands(text) {
        var out = [];
        var lines = String(text).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i].replace(/^\s+|\s+$/g, "");
            if (l === "") { continue; }
            l = l.replace(/^-\s*/, "");       // "- <id>: <name>"
            var idx = l.indexOf(": ");
            if (idx > 0) {
                out.push({ id: l.slice(0, idx), name: l.slice(idx + 2) });
            } else {
                out.push({ id: l, name: l });
            }
        }
        phoneCommands = out;
        if (_phoneCmdSrc !== "") {
            run.disconnectSource(_phoneCmdSrc);   // one-shot, like the app scan
            _phoneCmdSrc = "";
        }
    }

    // launch the KDE Connect settings app (pairing / enabling plugins)
    function openKdeConnect() {
        runOnce("kdeconnect-app");
    }

    // ------------------------------------------------------------------
    // Phone mirroring (scrcpy over Wi-Fi)
    // ------------------------------------------------------------------
    readonly property url scrcpyUrl: Qt.resolvedUrl("../code/scrcpy.sh")
    readonly property string scrcpyCmd: "sh " + shUrl(scrcpyUrl)
    readonly property string scrcpyStatusCmd: scrcpyCmd + " status"
    property bool mirroring: false

    function mirrorStart() {
        mirroring = true;                 // optimistic; the timer resyncs
        runOnce(scrcpyCmd + " start");
        mirrorCheckTimer.restart();
    }

    function mirrorStop() {
        mirroring = false;
        runOnce(scrcpyCmd + " stop");
        mirrorCheckTimer.restart();
    }

    // ask the helper whether a mirror is actually up (one-shot)
    function refreshMirrorState() {
        runOnce(scrcpyStatusCmd);
    }

    // QtObject has no default property, so the timer must be a property
    readonly property Timer mirrorCheckTimer: Timer {
        interval: 2500
        onTriggered: state.refreshMirrorState()
    }

    function parsePhoneNotifs(text) {
        var lines = String(text).split("\n");
        var out = [];
        for (var i = 0; i < lines.length; i++) {
            var f = lines[i].split("\u001f");
            if (f.length >= 4 && f[0] !== "") {
                out.push({
                    id: f[0], app: f[1],
                    title: f[2],
                    dismissable: f[3] === "1"
                });
            }
        }
        phoneNotifs = out;
        if (_phoneNotifSrc !== "") {
            run.disconnectSource(_phoneNotifSrc);   // one-shot: same safe
            _phoneNotifSrc = "";                    // pattern as the app scan
        }
    }

    // ------------------------------------------------------------------
    // Data plumbing (executable data engine)
    // ------------------------------------------------------------------
    readonly property url sysUrl: Qt.resolvedUrl("../code/sysmon.sh")
    readonly property url scanUrl: Qt.resolvedUrl("../code/scanapps.sh")
    readonly property url infoUrl: Qt.resolvedUrl("../code/sysinfo.sh")
    readonly property url favsUrl: Qt.resolvedUrl("../code/readfavs.sh")
    readonly property url osUrl: Qt.resolvedUrl("../code/osid.sh")
    readonly property url recentUrl: Qt.resolvedUrl("../code/recent.sh")
    readonly property string sysCmd: "sh " + shUrl(sysUrl)
    readonly property string scanCmd: "sh " + shUrl(scanUrl)
    readonly property string infoCmd: "sh " + shUrl(infoUrl)
    readonly property string favsCmd: "sh " + shUrl(favsUrl)
    readonly property string osCmd: "sh " + shUrl(osUrl)
    readonly property string recentCmd: "sh " + shUrl(recentUrl) + " list"

    // -------- running distro (panel icon + tooltips) --------
    // osid.sh reports "ID<TAB>Pretty Name" from /etc/os-release; the widget
    // bundles the matching logo and shows it as the default shortcut icon
    property string osId: ""       // arch | cachyos | ubuntu | linuxmint | manjaro | …
    property string osPretty: ""   // e.g. "Arch Linux"

    readonly property var osLogos: ({
        "arch": "os-arch.png",
        "cachyos": "os-cachyos.png",
        "ubuntu": "os-ubuntu.png",
        "linuxmint": "os-mint.png",
        "manjaro": "os-manjaro.png"
    })

    // bundled distro logo for the running OS, or "" when we have none
    function osLogo() {
        if (osId !== "" && osLogos[osId] !== undefined) {
            return Qt.resolvedUrl("../icons/" + osLogos[osId]).toString();
        }
        return "";
    }

    function parseOs(text) {
        var f = String(text).trim().split("\t");
        if (f[0] !== "" && f[0] !== undefined) { osId = f[0]; }
        if (f[1] !== undefined) { osPretty = f[1]; }
    }

    property int _seq: 0

    // configurable refresh rate (ms); wired from the widget settings
    property int refreshInterval: 1500

    // ------------------------------------------------------------------
    // System poll lifecycle
    // ------------------------------------------------------------------
    // The executable engine only runs while a source is connected, so the
    // system poll is tied to the popup: expanded → the user's refresh rate
    // (1.5 s by default), collapsed → a slow 10 s tick that still keeps the
    // compact tooltip roughly live. This keeps an idle desktop free of the
    // constant `sysmon.sh` spawn every 1.5 s.
    property bool sysPollForeground: false
    property bool _sysPollActive: false
    property int _sysPollInterval: 0

    function startSysPoll(ms) {
        if (ms === undefined) { ms = refreshInterval; }
        if (ms < 250) { ms = 250; }
        if (_sysPollActive && _sysPollInterval === ms) { return; }
        if (_sysPollActive) {
            run.disconnectSource(sysCmd);
            _sysPollActive = false;
        }
        _sysPollInterval = ms;
        _sysPollActive = true;
        // the plasma5support engine takes the polling rate from the data
        // source's interval property — connectSource() only accepts a name
        run.interval = ms;
        run.connectSource(sysCmd);
    }

    function stopSysPoll() {
        if (!_sysPollActive) { return; }
        _sysPollActive = false;
        _sysPollInterval = 0;
        run.disconnectSource(sysCmd);
    }

    // called from the popup's expandedChanged: fast while open, slow idle
    function setSysPollForeground(fg) {
        sysPollForeground = fg;
        startSysPoll(fg ? refreshInterval : 10000);
    }

    onRefreshIntervalChanged: {
        if (sysPollForeground) { startSysPoll(refreshInterval); }
    }

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
            if (state._phoneNotifSrc !== "" && base === state._phoneNotifSrc) {
                state.parsePhoneNotifs(out);     // one-shot: parsed, then closed
                return;
            }
            if (state._phoneCmdSrc !== "" && base === state._phoneCmdSrc) {
                state.parsePhoneCommands(out);   // one-shot: parsed, then closed
                return;
            }
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
            if (base === state.recentCmd) {
                state.parseRecent(out);
                disconnectSource(sourceName);
                return;
            }
            if (base === state.scrcpyStatusCmd) {
                state.mirroring = String(out).replace(/\s+$/, "") === "running";
                disconnectSource(sourceName);
                return;
            }
            if (base === state.infoCmd) {
                state.parseSysInfo(out);
                disconnectSource(sourceName);
                return;
            }
            if (base === state.osCmd) {
                state.parseOs(out);
                disconnectSource(sourceName);
                return;
            }
            disconnectSource(sourceName);        // fire & forget (launch, pin…)
        }
    }

    // The phone poll gets its OWN data source. phone.sh's poll takes ~2 s
    // (kdeconnect-cli plus several busctl/qdbus round-trips) — longer than
    // the system poll's 1.5 s tick. Sharing `run` made the executable engine
    // refuse the overlap ("Process … already running") on nearly every tick,
    // so the phone panel effectively starved. A separate source with a 5 s
    // interval keeps the poll self-consistent while `run` keeps its
    // user-configured (fast) rate for sysmon.
    readonly property P5Support.DataSource phoneRun: P5Support.DataSource {
        engine: "executable"
        interval: 5000
        onNewData: (sourceName, data) => {
            var out = data && data["stdout"] !== undefined ? String(data["stdout"]) : "";
            var base = String(sourceName).split(" #")[0];
            if (state._phoneSrc !== "" && base === state._phoneSrc) {
                state.parsePhone(out);           // keep connected: phone poll
            }
        }
    }

    function init() {
        startSysPoll(10000);     // slow idle tick until the popup opens
        rescanApps(true);
        readFavorites();
        readSysInfo();
        runOnce(osCmd);          // detect the distro once for the panel icon
        readRecent();
    }

    // The desktop-file scan is comparatively expensive, and the widget
    // re-scans on every open. Cache it for a short while so flipping the
    // menu open/closed repeatedly doesn't spawn scanapps.sh each time.
    property real _lastScanTime: 0

    function rescanApps(force) {
        var now = Date.now();
        if (!force && appList.length > 0 && (now - _lastScanTime) < 30000) {
            return;
        }
        _lastScanTime = now;
        runOnce(scanCmd);
    }

    function readFavorites() {
        runOnce(favsCmd);
    }

    // ------------------------------------------------------------------
    // Recently used apps (Kickoff-style history)
    // ------------------------------------------------------------------
    property var recentIds: []          // desktop ids, most recent first

    function readRecent() {
        runOnce(recentCmd);
    }

    function parseRecent(text) {
        var out = [];
        var lines = String(text).split("\n");
        for (var i = 0; i < lines.length; i++) {
            var id = lines[i].trim();
            if (id !== "" && out.indexOf(id) < 0) { out.push(id); }
        }
        recentIds = out;
    }

    // called from launch(): move the id to the top of the history, both in
    // memory (the UI updates instantly) and on disk (persists across sessions)
    function noteLaunch(id) {
        if (id === undefined || id === null || String(id) === "") { return; }
        id = String(id);
        var next = [id];
        for (var i = 0; i < recentIds.length && next.length < 12; i++) {
            if (recentIds[i] !== id) { next.push(recentIds[i]); }
        }
        recentIds = next;
        runOnce("sh " + shUrl(recentUrl) + " add " + sh(id));
    }

    function clearRecent() {
        recentIds = [];
        runOnce("sh " + shUrl(recentUrl) + " clear");
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
                cats: f[3], exec: f[4], path: f[5],
                generic: f[6] || "", keywords: f[7] || ""
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
                path: a.path, exec: a.exec,
                generic: a.generic, keywords: a.keywords
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

        // taskbar launchers are stored as "applications:<id>.desktop,…";
        // keep only the app entries (drop preferred:// etc.). `taskbarIds`
        // was referenced below but never defined, so this migration threw a
        // ReferenceError instead of seeding pins on first run.
        var taskbarIds = [];
        if (taskbarLine !== "") {
            var titems = taskbarLine.split(",");
            for (var k = 0; k < titems.length; k++) {
                var tu = titems[k].trim();
                if (tu.indexOf("applications:") === 0) {
                    var tid = tu.slice(13);
                    if (tid !== "" && taskbarIds.indexOf(tid) < 0) { taskbarIds.push(tid); }
                }
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
        // Launch the app exactly like the native KDE application launcher
        // (Kickoff): KIO's ApplicationLauncherJob → KProcessRunner registers
        // the process with the user systemd manager (app-<name>@<uuid>
        // .service, Slice=app.slice) or forks it fully detached; stdio always
        // lands on the journal or /dev/null — never on a plasmashell pipe or
        // a GLib journald stream that can be closed underneath the app (that
        // is what made Electron apps such as Discord crash with
        // "write EPIPE"). The whole mechanism lives in launchapp.sh because
        // the executable engine runs command strings without a shell (no
        // pipes, no || fallbacks): one plain "sh <script> <args>" call, the
        // same shape as this widget's other engine commands.
        runOnce("sh " + shUrl(Qt.resolvedUrl("../code/launchapp.sh"))
              + " " + sh(String(path)) + " " + sh(String(id)));
        noteLaunch(id);
        requestClose();
    }

    // open the folder that contains a .desktop file
    function openContainingFolder(path) {
        var p = String(path || "");
        var idx = p.lastIndexOf("/");
        if (idx <= 0) { return; }
        runOnce("xdg-open " + sh(p.slice(0, idx)));
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
