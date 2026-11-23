# AINABOX — Local Portable Sovereign AI
# Copyright (C) 2026 Michele Canova <bastian@ainabox.it>
# Licensed under GPL-3.0-or-later

"""BACKUP ESTERNO COMPLETO — T7 (copie fuori-box)
Motore: rsync-dir (resumable, verificabile per-file) [1].
Progress bar reale: rsync --info=progress2 → SSE [2].
Riusa: _lock/_unlock/_sudo da servizi.py [3].
Pattern: registra(app) come gli altri moduli [2].
"""
import os, re, json, asyncio, subprocess, time
from datetime import datetime
from pathlib import Path
from fastapi import HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from moduli import servizi  # _lock, _unlock, _sudo [3]

# ── Costanti ──────────────────────────────────────────────
SRC = "/mnt/ainabox"
WRAPPER = "/mnt/ainabox/vetrina_zone/bin/backup_op.sh"
LOCK_NAME = "backup"

EXCLUDES = [
    "comfy_zone/ComfyUI/models/",
    "*/comfy_zone/ComfyUI/models/",
    "*/comfy_zone/",
    "ollama_zone/models/",
    "*/ollama_zone/models/",
    "modelli/",
]

# ── Progress parsing (locale-IT) ──────────────────────────
# Riga progress: "     20.971.520 100%    2,17GB/s    0:00:00 (xfr#1...)"
#   punti = migliaia, virgola = decimale, unità = KB/s MB/s GB/s TB/s
_RS_PROGRESS = re.compile(
    r'^\s+(\d[\d.]*\d)\s+(\d+)%\s+([\d.,]+)([KMGT]?)B/s'
)
_SPEED_MULT = {'': 1, 'K': 1024, 'M': 1024**2, 'G': 1024**3, 'T': 1024**4}
_RS_SKIP = re.compile(
    r'^(sending|sent\s|total\s|Number|Average|Directory|created|deleted)'
)


class BackupJob:
    def __init__(self, job_id, total_bytes, dry_run):
        self.job_id          = job_id
        self.total_bytes     = total_bytes
        self.completed_bytes = 0
        self.cur_path        = ""
        self.cur_file_size   = 0
        self.cur_pos         = 0
        self.speed           = 0.0
        self.state           = "running"
        self.err             = ""
        self.dry_run         = dry_run
        self.artifact        = ""

    def transferred(self):
        return self.completed_bytes + self.cur_pos

    def pct(self):
        if self.total_bytes == 0:
            return 0.0 if self.state == "running" else 100.0
        return min(100.0, self.transferred() / self.total_bytes * 100)

    def eta_s(self):
        if self.speed < 1:
            return 0
        return int(max(0, self.total_bytes - self.transferred()) / self.speed)


def _close_file(job):
    if job.cur_path and job.cur_file_size > 0:
        job.completed_bytes += job.cur_file_size
    job.cur_file_size = 0
    job.cur_pos = 0


def _parse_line(raw, job):
    if not raw.strip():
        return
    # Riga progress (inizia con spazi)
    if raw[0] == ' ':
        m = _RS_PROGRESS.match(raw)
        if m:
            size_s, pct_s, spd_s, spd_u = m.groups()
            fsize = int(size_s.replace('.', ''))
            pct   = int(pct_s)
            spd   = float(spd_s.replace(',', '.'))
            job.speed = spd * _SPEED_MULT.get(spd_u, 1)
            if fsize != job.cur_file_size:
                _close_file(job)
                job.cur_file_size = fsize
            job.cur_pos = int(fsize * pct / 100)
        return
    # Riga senza spazi in testa
    if _RS_SKIP.match(raw):
        return
    # filename → chiudi precedente
    _close_file(job)
    job.cur_path = raw.strip()


# ── Models ────────────────────────────────────────────────
class BackupRequest(BaseModel):
    dest: str
    nome: str | None = None
    dry_run: bool = True

_JOBS: dict = {}

# ── Helpers ───────────────────────────────────────────────
def _free_gb(path):
    st = os.statvfs(path)
    return round(st.f_bavail * st.f_frsize / (1024**3), 1)



# ── Registry dei percorsi manuali ─────────────────────────
REGISTRY_PATHS = [
    Path("/mnt/ainabox/vetrina_zone/.backup_dests.json"),
    Path.home() / ".config" / "vetrina" / "backup_dests.json",
]


def _load_dests():
    for p in REGISTRY_PATHS:
        try:
            if p.is_file():
                data = json.loads(p.read_text())
                if isinstance(data, list):
                    return [d for d in data if isinstance(d, str) and d]
        except (OSError, ValueError):
            pass
    return []


def _add_dest(dest):
    if not dest or not isinstance(dest, str):
        return
    dest = dest.rstrip('/')
    if not dest:
        return
    for p in REGISTRY_PATHS:
        try:
            existing = []
            if p.is_file():
                try:
                    data = json.loads(p.read_text())
                    if isinstance(data, list):
                        existing = [d for d in data if isinstance(d, str) and d]
                except (OSError, ValueError):
                    existing = []
            if dest not in existing:
                existing.append(dest)
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(json.dumps(existing))
            try:
                p.chmod(0o644)
            except OSError:
                pass
            return
        except (OSError, PermissionError):
            continue


def _detect_destinations():
    results = []
    _cands = [
        ('/home/AINABOX_backups', 'AINABOX Backups'),
        ('/media', 'Dischi esterni'),
        ('/run/media', 'Dischi esterni'),
    ]
    _known = [c[0] for c in _cands]
    for _d in _load_dests():
        if _d not in _known:
            _cands.append((_d, _d))
    _registered = set(_load_dests())
    for path, label in _cands:
        if path not in _registered and not os.path.isdir(path):
            continue
        if path == SRC or SRC.startswith(path + "/"):
            continue
        try:
            if path in _registered or os.access(path, os.R_OK):
                results.append({"path": path, "label": label, "free_gb": _free_gb(path)})
        except OSError:
            pass
    return results


def _build_cmd(dest, nome, dry_run):
    stamp = datetime.now().strftime("%Y.%m.%d_%H%M")
    name = nome or stamp
    target = f"{dest}/{name}"
    cmd = ["sudo", "-n", "bash", WRAPPER, "rsync", dest, name]
    if dry_run:
        cmd.append("dry")
    for ex in EXCLUDES:
        cmd.extend(["--exclude", ex])
    return cmd, target


def _write_restore(target_dir):
    """Genera RESTORE.md + restore.sh in /tmp, poi copia con sudo rsync.
    Funziona su any X, any host."""
    import tempfile, subprocess, os
    stage = tempfile.mkdtemp(prefix="restore_")
    with open(os.path.join(stage, "RESTORE.md"), "w") as f:
        f.write(f"# RIPRISTINO AINABOX — backup del {datetime.now().strftime('%Y-%m-%d')}\n")
        f.write(f"\nQuesto disco contiene la tua AINABOX. Per riaverla:\n")
        f.write(f"\n  1. Collega questo disco a un host con AINABOX installata.\n")
        f.write(f'  2. Copia il contenuto nella posizione di AINABOX:\n')
        f.write(f'       sudo rsync -avh "{target_dir}/" /mnt/ainabox/\n')
        f.write(f"  3. Riapri AINABOX:  apri_ainabox\n")
    with open(os.path.join(stage, "restore.sh"), "w") as f:
        f.write('#!/bin/bash\n')
        f.write(f'sudo rsync -avh "{target_dir}/" /mnt/ainabox/\n')
    r = subprocess.run(
        ["sudo", "-n", "bash", WRAPPER, "cp", target_dir, stage],
        capture_output=True, text=True, timeout=15
    )
    subprocess.run(["rm", "-rf", stage], capture_output=True, timeout=5)
    if r.returncode != 0:
        print(f"WARNING: _write_restore fallito: {r.stderr.strip()}")

async def _run(job, dest, nome, dry_run):
    try:
        cmd, target = _build_cmd(dest, nome, dry_run)
        job.artifact = target

        # ── Dry-run: no progress, solo wait ──
        if dry_run:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
            await proc.wait()
            if proc.returncode == 0:
                job.state = "done"
            else:
                job.state = "error"
                job.err = f"rsync dry-run exit {proc.returncode}"
            return

        # ── Run reale: rsync + polling du sulla destinazione ──
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )

        # Drain stderr in background (per eventuali errori, non per progress)
        async def _drain():
            if proc.stderr is None:
                return
            tail = []
            async for line in proc.stderr:
                tail.append(line.decode(errors='replace').rstrip())
                if len(tail) > 50:
                    del tail[:10]
            job.err_tail = "\n".join(tail[-30:])
        task_stderr = asyncio.create_task(_drain())

        # ── Polling loop ──
        last_bytes = 0
        last_t = time.time()
        while proc.returncode is None:
            try:
                p2 = await asyncio.create_subprocess_exec(
                    "du", "-sb", target,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.DEVNULL,
                )
                out, _ = await p2.communicate()
                if out:
                    cur = int(out.decode().split()[0])
                    now = time.time()
                    if last_bytes > 0 and now > last_t:
                        job.speed = (cur - last_bytes) / (now - last_t)
                    last_bytes = cur
                    last_t = now
                    job.completed_bytes = cur
                    job.cur_pos = 0
                    # file corrente (ultimo modificato negli ultimi 90s)
                    p3 = await asyncio.create_subprocess_exec(
                        "find", target, "-type", "f", "-mmin", "-2",
                        stdout=asyncio.subprocess.PIPE,
                        stderr=asyncio.subprocess.DEVNULL,
                    )
                    out3, _ = await p3.communicate()
                    if out3:
                        files = out3.decode().strip().split('\n')
                        if files and files[0]:
                            job.cur_path = files[0]
            except (ValueError, IndexError, ProcessLookupError, FileNotFoundError):
                pass
            await asyncio.sleep(2)

        await proc.wait()
        await task_stderr

        # du finale
        try:
            p2 = await asyncio.create_subprocess_exec(
                "du", "-sb", target,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            out, _ = await p2.communicate()
            if out:
                job.completed_bytes = int(out.decode().split()[0])
        except (ValueError, IndexError):
            pass

        if proc.returncode == 0:
            job.state = "done"
            _write_restore(target)
        else:
            job.state = "error"
            job.err = f"rsync exit {proc.returncode}"
            if getattr(job, "err_tail", ""):
                job.err += "\n" + job.err_tail

    except Exception as e:
        job.state = "error"
        job.err = str(e)
    finally:
        servizi._unlock(job.fd)


# ── Endpoints ─────────────────────────────────────────────
def registra(app):

    @app.post("/api/backup")
    async def start_backup(body: BackupRequest):
        try:
            fd = servizi._lock()
        except Exception:
            raise HTTPException(409, "Un backup è già in corso")
        body.dest = "/home/AINABOX_backups"
        _add_dest(body.dest)

        total_bytes = 0
        if not body.dry_run:
            p = await asyncio.create_subprocess_exec(
                "sudo", "-n", "bash", WRAPPER, "du", "-sb", SRC,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            out, _ = await p.communicate()
            if out:
                try:
                    total_bytes = int(out.decode().split()[0])
                except (ValueError, IndexError):
                    total_bytes = 0

        job_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        job = BackupJob(job_id, total_bytes, body.dry_run)
        _JOBS[job_id] = job
        job.fd = fd
        asyncio.create_task(_run(job, body.dest, body.nome, body.dry_run))

        return {"job_id": job_id, "dry_run": body.dry_run,
                "total_gb": round(total_bytes / 1024**3, 1)}

    @app.get("/api/backup/stream/{job_id}")
    async def backup_stream(job_id: str):
        job = _JOBS.get(job_id)
        if job is None:
            raise HTTPException(404, "job non trovato")

        async def _gen():
            while True:
                p = {
                    "state": job.state,
                    "pct": round(job.pct(), 1),
                    "gb": round(job.transferred() / 1024**3, 1),
                    "total_gb": round(job.total_bytes / 1024**3, 1),
                    "speed": f"{job.speed/1024**2:.1f} MB/s" if job.speed else "—",
                    "eta": f"{job.eta_s()//60}m {job.eta_s()%60}s" if job.eta_s() else "—",
                    "file": job.cur_path[-60:],
                    "dry_run": job.dry_run,
                }
                if job.state == "error":
                    p["err"] = job.err
                if job.state == "done":
                    p["artifact"] = job.artifact
                yield f"data: {json.dumps(p)}\n\n"
                if job.state != "running":
                    break
                await asyncio.sleep(1.0)

        return StreamingResponse(
            _gen(), media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    @app.get("/api/backup/status/{job_id}")
    def status(job_id: str):
        if job_id not in _JOBS:
            raise HTTPException(404, "job non trovato")
        j = _JOBS[job_id]
        return {"state": j.state, "pct": round(j.pct(), 1),
                "gb": round(j.transferred()/1024**3, 1),
                "total_gb": round(j.total_bytes/1024**3, 1),
                "err": j.err, "dry_run": j.dry_run,
                "artifact": j.artifact}

    @app.get("/api/backup/destinations")
    def destinations():
        return _detect_destinations()


    @app.get("/api/backup/archives")
    def archives(dest: str = ""):
        """Lista i backup esistenti nella destinazione + dimensione."""
        results = []
        dests = _detect_destinations()
        if not dests and not dest:
            for _p in ["/mnt/Datadisk", "/mnt/NAS"]:
                if os.path.isdir(_p) and os.access(_p, os.R_OK):
                    dests.append({"path": _p, "label": _p, "free_gb": 0})
        safe_name = re.compile(r'^[A-Za-z0-9_.-]+$')
        if dest and os.path.isdir(dest):
            dests.insert(0, {"path": dest, "label": dest, "free_gb": 0})
        for d in dests:
            dp = Path(d["path"])
            import subprocess as _sp_ls
            r_ls = _sp_ls.run(['sudo', '-n', 'bash', WRAPPER, 'ls', str(dp)],
                              capture_output=True, text=True, timeout=10)
            if r_ls.returncode != 0:
                continue
            _names = [n for n in r_ls.stdout.strip().split(chr(10)) if n and n not in ('.', '..')]
            if not _names:
                continue
            try:
                for _n in sorted(_names, reverse=True):
                    entry = dp / _n
                    if not safe_name.match(_n):
                        continue
                    if "_AINABOX" not in _n and "backup_T7" not in _n:
                        continue
                    # dimensione
                    import subprocess as _sp
                    du = _sp.run(["sudo", "-n", "bash", WRAPPER, "du", "-sh", str(entry)],
                                capture_output=True, text=True, timeout=120)
                    size = du.stdout.strip().split()[0] if du.stdout else "?"
                    results.append({
                        "name": entry.name,
                        "path": str(entry),
                        "dest": d["label"],
                        "size": size,
                    })
            except (PermissionError, OSError):
                # Fallback: listare via root (wrapper ls)
                import subprocess as _sp2
                r2 = _sp2.run(['sudo', '-n', 'bash', WRAPPER, 'ls', str(dp)],
                              capture_output=True, text=True, timeout=10)
                if r2.returncode == 0:
                    for name in r2.stdout.strip().split('\n'):
                        if not name or name in ('.', '..'):
                            continue
                        entry = dp / name
                        if not entry.is_dir():
                            continue
                        if not safe_name.match(name):
                            continue
                        du2 = _sp2.run(['sudo', '-n', 'bash', WRAPPER, 'du', '-sh', str(entry)],
                                      capture_output=True, text=True, timeout=120)
                        size2 = du2.stdout.strip().split()[0] if du2.stdout else '?'
                        results.append({'name': name, 'path': str(entry),
                                        'dest': d['label'], 'size': size2})
        return results

    @app.delete("/api/backup/archive/{name}")
    def delete_archive(name: str, dest: str = ""):
        """Elimina un backup. Solo nomi validi, solo dentro destinazioni note."""
        safe_name = re.compile(r'^[A-Za-z0-9_.-]+$')
        if not safe_name.match(name):
            raise HTTPException(400, "Nome non valido")
        if name in (".", "..", "/") or "/" in name or ".." in name:
            raise HTTPException(400, "Path non consentito")
        # deve essere dentro una destinazione conosciuta
        dests = _detect_destinations()
        if not dests and not dest:
            for _p in ["/mnt/Datadisk", "/mnt/NAS"]:
                if os.path.isdir(_p) and os.access(_p, os.R_OK):
                    dests.append({"path": _p, "label": _p, "free_gb": 0})
        target = None
        if dest and os.path.isdir(dest):
            dests.insert(0, {"path": dest, "label": dest, "free_gb": 0})
        for d in dests:
            candidate = Path(d["path"]) / name
            if candidate.is_dir() and (candidate.name == name):
                target = candidate
                break
        if target is None:
            raise HTTPException(404, "Backup non trovato")
        import subprocess as _sp
        r = _sp.run(["sudo", "-n", "bash", WRAPPER, "rm", str(target.parent), target.name],
                    capture_output=True, text=True, timeout=300)
        if r.returncode != 0:
            raise HTTPException(500, f"Errore rimozione: {r.stderr.strip()}")
        return {"deleted": name, "path": str(target)}

    @app.get("/api/backup/estimate")
    def estimate():
        p = subprocess.run(["du", "-sh", SRC], capture_output=True, text=True, timeout=120)
        return {"source": SRC,
                "size": p.stdout.strip().split()[0] if p.stdout else "?"}
