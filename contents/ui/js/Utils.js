.pragma library

var ACCENT_A = "#7C5CFF";
var ACCENT_B = "#22D3EE";

var CATS = {
    "AudioVideo":  { name: "Multimedia",  icon: "applications-multimedia" },
    "Audio":       { name: "Multimedia",  icon: "applications-multimedia" },
    "Video":       { name: "Multimedia",  icon: "applications-multimedia" },
    "Development": { name: "Development", icon: "applications-development" },
    "Education":   { name: "Education",   icon: "applications-education" },
    "Game":        { name: "Games",       icon: "applications-games" },
    "Graphics":    { name: "Graphics",    icon: "applications-graphics" },
    "Network":     { name: "Internet",    icon: "applications-internet" },
    "Office":      { name: "Office",      icon: "applications-office" },
    "Science":     { name: "Science",     icon: "applications-science" },
    "Settings":    { name: "Settings",    icon: "preferences-desktop" },
    "System":      { name: "System",      icon: "applications-system" },
    "Utility":     { name: "Accessories", icon: "applications-utilities" }
};

var ORDER = [
    "Accessories", "Development", "Internet", "Multimedia", "Office",
    "Graphics", "Games", "Science", "Education", "System", "Settings", "Other"
];

function resolveCat(categories) {
    var parts = (categories || "").split(";");
    for (var i = 0; i < parts.length; i++) {
        if (CATS[parts[i]]) { return CATS[parts[i]]; }
    }
    return { name: "Other", icon: "applications-other" };
}

function catOrder(name) {
    var i = ORDER.indexOf(name);
    return i < 0 ? 99 : i;
}

function fmtSpeed(kbs) {
    if (kbs >= 1024 * 1024) { return (kbs / 1024 / 1024).toFixed(2) + " GB/s"; }
    if (kbs >= 1024) { return (kbs / 1024).toFixed(1) + " MB/s"; }
    if (kbs >= 100) { return Math.round(kbs) + " KB/s"; }
    return kbs.toFixed(1) + " KB/s";
}

function fmtSize(mb) {
    if (mb >= 10240) { return Math.round(mb / 1024) + " GB"; }
    if (mb >= 1024) { return (mb / 1024).toFixed(1) + " GB"; }
    return Math.round(mb) + " MB";
}

function fmtMs(us) {
    var s = Math.floor(us / 1000000);
    var m = Math.floor(s / 60);
    s = s % 60;
    return m + ":" + (s < 10 ? "0" : "") + s;
}

function fmtUptime(sec) {
    var d = Math.floor(sec / 86400);
    var h = Math.floor((sec % 86400) / 3600);
    var m = Math.floor((sec % 3600) / 60);
    if (d > 0) { return d + "d " + h + "h"; }
    if (h > 0) { return h + "h " + m + "m"; }
    return m + "m";
}
