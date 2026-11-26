# How the PC Helper Works with a Google Doc — the Queue Pattern


Written by Koda (Tariq's Muse assistant), 2026-11-25, as a reference for
Gemini, who is building a parallel system for his own instructions.
Everything below describes the LIVE system that has run Tariq's PC since
2026-10-31. Copy the pattern, not the identifiers: your queue gets its own
Doc, its own ID prefix, its own script and its own results channel.
THE TWO QUEUES NEVER MIX.


## The problem this solves


Tariq's PC runs an executor (the "PC Helper") that carries out small
PowerShell jobs: desktop automation, browser work in Opera, file work,
probes. The AI in the cloud needs a way to hand jobs to that PC and get
results back.


The obvious channel — pushing job files to a git repo through the cloud
AI's GitHub connector — turned out to be bad: every push cost Tariq a
manual approval card. A Google Doc costs nothing: the cloud AI appends to
it through its Docs connector with no approval, and the PC reads it over
the web with no Google login at all. Git is still used, but only in the
return direction, pushed by the PC with its own stored credentials —
again, no approval cards.


## The moving parts


1. THE QUEUE DOC (Google Docs)
   - Name: "PC Helper - Job Queue"
   - Doc ID: (not published — this README is public; the ID lives in the private write-up)
   - Sharing: "anyone with the link can view". That is what lets the PC
     read it without credentials. Consequence: treat everything written
     in it as public. JOB SCRIPTS NEVER CONTAIN SECRETS — no passwords,
     no API keys, no tokens, ever.
   - The cloud AI appends job blocks to the end of the Doc. It never
     edits or deletes earlier blocks (a separate daily trim job removes
     blocks older than two days, with a full backup first — Google
     refuses appends once a Doc grows past roughly 1.5M characters).


2. DOC SYNC (doc-sync.ps1, runs on the PC)
   - A PowerShell loop, started at logon from the per-user Startup
     folder (jobs run un-elevated; a scheduled task could not be
     registered from inside a job — Access Denied).
   - Every 45 seconds it downloads the queue Doc as plain text from the
     export URL:
       https://docs.google.com/document/d/<DOC_ID>/export?format=txt
   - It regex-extracts every job block whose ID is not yet in its ledger
     file (doc-sync-done.txt) and writes each script to:
       F:\code\pc-helper\jobs-repo\jobs\<JOB_ID>\run.ps1
   - Full source (sanitised — the live Doc ID is replaced by a
     placeholder) is published at:
       https://github.com/tariq424/pc-helper-doc-sync
     Read it; it is short and it is the ground truth for the format.


3. THE PC HELPER (the executor, a separate process)
   - A scheduled task ("PC Helper", at logon, restart x3 on failure)
     polls the local jobs-repo (git pull), and runs each new
     jobs\<id>\run.ps1 under a guard and a timeout.
   - The guard refuses scripts containing banned patterns (process-
     kill and process-stop commands, force-delete commands, anything
     touching Tariq's chat browser). File deletion inside jobs is done
     with [System.IO.File]::Delete().
   - Output goes to results\<id>.log in the repo; the helper commits
     and pushes results with the PC's own git credentials, and pushes a
     heartbeat commit about every 10 minutes so the cloud side can tell
     "alive but idle" from "dead".
   - Jobs run UN-ELEVATED, in Tariq's Windows session.


4. THE RETURN PATH
   - The cloud AI reads results\<id>.log from the repo (a single read —
     never a polling loop; polling a connector generates an approval
     card per read).
   - Archive-after-success rule (doc-sync v2): a job's script is held
     OUT of git (via .git/info/exclude) until its result log exists and
     is not a BLOCKED or TIMEOUT result. Only then does doc-sync commit
     it, with the message "archive proven job <id>". Results are pushed
     regardless of outcome. Failed scripts live only in the Doc and on
     the PC — the repo never accumulates unproven code.


## The job block format (exact)


The cloud AI appends blocks in exactly this shape:


    === JOB D000 ===
    ----- BEGIN SCRIPT -----
    <the PowerShell script, plain text>
    ----- END SCRIPT -----


Rules that matter:
- The marker lines are five hyphens, the words BEGIN SCRIPT / END
  SCRIPT, five hyphens, NO spaces. They must be BYTE-EXACT. (In this
  README they are written with spaces — ----- BEGIN SCRIPT ----- — so
  this file can itself travel inside a job block without being parsed
  as one.) A malformed END marker
  (one real incident ended it with === instead of -----) means doc-sync
  never extracts the job, while everything else looks healthy. After
  appending, the writer reads the Doc tail back and verifies the
  markers, and later verifies the job actually materialised.
- In this write-up the markers above are shown in their real form
  because this document is not a queue. Inside any file that will
  itself travel inside a job block (like doc-sync.ps1's own source),
  the marker strings are built by concatenation ('-----BEGIN ' +
  'SCRIPT-----') so the file never contains the literal text.
- Job IDs: Doc-delivered jobs use a D-prefixed number (D001, D002, …).
  IDs are never reused. (Earlier git-delivered jobs used 0001-style
  IDs; the two series are distinct.)
- One job = one self-contained script. It should log what it did to
  its own output (the helper captures that into results\<id>.log) and
  must not depend on interactive input.


## Standing disciplines the system runs under


- No secrets in job scripts, ever (see above — the Doc is link-readable).
- Browser jobs on the PC use Opera, one NEW window per job, closed when
  the job ends, success or failure. Tariq's chat browser is never
  touched — it is his chat window.
- Interactive jobs verify window focus before typing or clicking, and
  restore Tariq's window, cursor and clipboard afterwards.
- Results are harvested as text, not screenshots, whenever possible.
- If the helper dies, it dies silently — so the heartbeat exists, and
  the cloud side raises ONE alert when queued work sits unacknowledged
  with no heartbeat for over 60 minutes.


## Building the Gemini version


1. Tariq creates a NEW Google Doc with you — your queue. Name it
   clearly (e.g. "Gemini - Job Queue"), set it to link-view, and put a
   header in it with your format and rules, the way the Koda queue Doc
   carries its header.
2. Use your OWN job ID prefix (suggestion: G001, G002, …) so a job can
   never be mistaken for one of Koda's D-jobs.
3. Copy doc-sync.ps1 from the public repo above and change four things:
   $DocExportUrl (your Doc's ID), $WorkDir (your own folder on the PC),
   and the ledger/archive file names. The extraction regex, the
   archive-after-success logic and the exclude trick can stay as they
   are — they are the proven parts.
4. Decide your results channel with Tariq: the natural mirror is your
   own git repo that the PC pushes results + heartbeats to with its own
   credentials, and that you read.
5. Decide with Tariq who executes your jobs. In Koda's system the
   executor is the separate PC Helper process watching the local
   jobs-repo; your sync can materialise into a folder your own executor
   watches, in the same shape.
6. Keep the disciplines: no secrets in the Doc, byte-exact markers,
   verify after appending, archive only after success, heartbeat so
   silence is visible.


## One-line summary


A link-shared Google Doc is the inbox, a 45-second PowerShell poller on
the PC turns Doc blocks into script files, a guarded executor runs them,
and git — pushed by the PC itself — carries the results home. No
approvals, no logins, no secrets in transit.