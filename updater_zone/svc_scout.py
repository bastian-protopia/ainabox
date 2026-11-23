#!/usr/bin/env python3

# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

"""svc_scout.py v1 - IL ricognitore
Legge watchlist, interroga HuggingFace (tree API), scrive manifesti.
NON scarica. NON installa. SOLO a comando (regola 12).
Lancio: sudo -u svc_updater python3 /mnt/Data/updater_zone/svc_scout.py
AIBOX = open('/etc/ainabox/dest').read().strip()
Contratto manifesto: come lo legge svc_updater.sh (file[].url/sha256/size).
"""
import json, os, sys
from datetime import datetime, timezone
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError

MANIFESTI_DIR = AIBOX + "/updater_zone/manifesti"
WATCHLIST     = AIBOX + "/updater_zone/watchlist.json"
UA            = "svc-scout/1.0 Parnassos-T7"

MODE_NET_FILE = AIBOX + "/network_zone/MODE_NET"
def _verifica_connessione():
    try:
        mode = open(MODE_NET_FILE).read().strip()
    except Exception:
        mode = "offline"
    if mode == "offline":
        print("OFFLINE — non interrogo HF. Toggle: Vetrina > Connessioni.")
        sys.exit(0)
_verifica_connessione()


HF_TOKEN_FILE = AIBOX + "/updater_zone/.secrets/HF_TOKEN"

def _hf_token():
    """Legge il token HF gated se presente. Ritorna stringa o None."""
    try:
        with open(HF_TOKEN_FILE) as f:
            t = f.read().strip()
            return t if t else None
    except (FileNotFoundError, PermissionError):
        return None


def ts():
    return datetime.now(timezone.utc).astimezone().isoformat()


def get_json(url, timeout=30):
    headers = {"User-Agent": UA}
    if "huggingface.co" in url:
        tok = _hf_token()
        if tok:
            headers["Authorization"] = "Bearer " + tok
    req = Request(url, headers=headers)
    with urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def hf_tree(repo):
    """Ritorna {filename: (sha256, size)} dei .gguf nel repo (main)."""
    url = "https://huggingface.co/api/models/" + repo + "/tree/main"
    out = {}
    for f in get_json(url):
        p = f.get("path", "")
        if p.endswith(".gguf") and "lfs" in f:
            out[p] = (f["lfs"]["oid"], f.get("size", 0))
    return out


def write_manifest(m):
    os.makedirs(MANIFESTI_DIR, exist_ok=True)
    p = os.path.join(MANIFESTI_DIR, m["id"] + ".json")
    with open(p, "w") as f:
        json.dump(m, f, indent=2)
    print("  manifest -> " + p)


def scout_hf(entry):
    repo   = entry["parametri"]["repo"]
    files  = entry["parametri"]["file"]
    dest   = entry.get("destinazione", "ollama_zone")
    sub    = entry.get("sottocartella", "")
    tree   = hf_tree(repo)
    out    = []
    for fn in files:
        if fn not in tree:
            print("  WARN non nel repo: " + fn)
            continue
        sha, size = tree[fn]
        url = "https://huggingface.co/" + repo + "/resolve/main/" + fn
        out.append({"ruolo": "model", "file": fn, "url": url,
                    "sha256": sha, "size": size})
        print("  OK %-40s %.2f GB  %s" % (fn, size / 1e9, sha[:16] + "..."))
    if not out:
        return None
    return {
        "id": entry["id"], "tipo": "modello",
        "destinazione": dest, "file": out,
        "sottocartella": sub,
        "parametri": entry["parametri"],
        "generato": ts(), "fonte": "huggingface"
    }


def main():
    print("=== svc_scout v1 ===")
    print(ts() + "\n")
    if not os.path.exists(WATCHLIST):
        print("ERRORE: watchlist non trovata: " + WATCHLIST)
        sys.exit(1)
    wl = json.load(open(WATCHLIST))
    if not wl:
        print("Watchlist vuota.")
        sys.exit(0)
    print(str(len(wl)) + " entry da sfogliare\n")
    n = 0
    for e in wl:
        fonte = e.get("fonte", "").lower()
        print("=" * 40)
        print(e.get("id", "?") + "  [" + fonte + "]")
        if fonte == "huggingface":
            m = scout_hf(e)
            if m:
                write_manifest(m)
                n += 1
        elif fonte == "ollama":
            print("  v2 (blobs+index). Usa HF per ora.")
        else:
            print("  fonte sconosciuta: " + fonte)
    print("\n=== FINE: " + str(n) + " manifesti scritti ===")


def cmd_diff():
    import glob
    zones = {}
    for f in sorted(glob.glob(AIBOX + "/*_zone/VERSION")):
        zone = f.replace(AIBOX + "/","").replace("_zone/VERSION","")
        zones[zone] = {"current": open(f).read().strip(), "latest": None, "changed": False}
    if os.path.exists(WATCHLIST):
        wl = json.load(open(WATCHLIST))
        for e in wl:
            if e.get("fonte") == "huggingface":
                repo = e.get("parametri",{}).get("repo","")
                if repo:
                    try:
                        data = get_json("https://huggingface.co/api/models/"+repo)
                        latest = data.get("sha","unknown")
                        z = e.get("destinazione","?").replace("_zone","")
                        if z in zones:
                            zones[z]["latest"] = latest
                            zones[z]["changed"] = (zones[z]["current"] != latest)
                    except Exception:
                        pass
    print(json.dumps({"ok":True,"diffs":list(zones.values())}))
def cmd_elenca():
    results = []
    if os.path.exists(WATCHLIST):
        results = json.load(open(WATCHLIST))
    print(json.dumps({"ok":True,"disponibili":results}))
def cmd_cerca(q):
    results = []
    if os.path.exists(WATCHLIST):
        wl = json.load(open(WATCHLIST))
        for e in wl:
            if q.lower() in e.get("id","").lower() or q.lower() in json.dumps(e).lower():
                results.append(e)
    print(json.dumps({"ok":True,"risultati":results}))
if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "--diff": cmd_diff()
        elif cmd == "--elenca": cmd_elenca()
        elif cmd == "--cerca" and len(sys.argv) > 2: cmd_cerca(sys.argv[2])
        else: main()
    else:
        main()
