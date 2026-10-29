#!/bin/sh
# Scans .desktop entries and emits one line per app:
#   id <US> name <US> icon <US> categories <US> exec <US> path
# where <US> is the ASCII unit-separator (0x1f).

SEP=$(printf '\037')

find /usr/local/share/applications \
     /usr/share/applications \
     /var/lib/flatpak/exports/share/applications \
     "$HOME/.local/share/flatpak/exports/share/applications" \
     "$HOME/.local/share/applications" \
     -maxdepth 1 \( -type f -o -xtype f \) -name '*.desktop' 2>/dev/null | sort | xargs -r -d '\n' awk -v sep="$SEP" '
FNR==1 {
    if (started) { emit(); }
    inmain=0; name=""; icon=""; execmd=""; cats=""; nd=0; hid=0; osi=""; nsi=""; type="";
    path=FILENAME; id=path; sub(/.*\//,"",id);
    started=1;
}
/^\[Desktop Entry\]/ { inmain=1; next }
/^\[/               { inmain=0; next }
inmain && /^Type=/      { type=substr($0,6) }
inmain && /^Name=/      { if (name=="")   name=substr($0,6) }
inmain && /^Icon=/      { if (icon=="")   icon=substr($0,6) }
inmain && /^Exec=/      { if (execmd=="") execmd=substr($0,6) }
inmain && /^Categories=/{ if (cats=="")  cats=substr($0,12) }
inmain && /^NoDisplay=true/{ nd=1 }
inmain && /^Hidden=true/  { hid=1 }
inmain && /^OnlyShowIn=/  { osi=substr($0,11) }
inmain && /^NotShowIn=/   { nsi=substr($0,11) }
function emit() {
    if (type=="Application" && nd==0 && hid==0 && name!="" && execmd!="") {
        if (osi=="" || index(osi,"KDE")>0 || index(osi,"GNOME")>0) {
            if (index(nsi,"KDE")==0) {
                printf "%s%s%s%s%s%s%s%s%s%s\n", id,sep,name,sep,icon,sep,cats,sep,execmd,sep,path
            }
        }
    }
}
END { if (started) emit() }
'
