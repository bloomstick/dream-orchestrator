# PowerShell script traps (paid for in production)

Two failure classes that look like anything except what they are. Check
these first when a `.ps1` misbehaves; both were diagnosed the hard way
during the Architect INSTALL.ps1 work.

## 1. Non-ASCII bytes break Win-PS5.1 parsing by position

UTF-8 files without BOM are read as ANSI; a multibyte character (em-dash,
etc.) can cascade into bogus errors far downstream (`Missing ')'`,
`unterminated string`). The file is valid, the checker output is not lying
about *a* problem — it is lying about *where*.

- Convention: **scripts stay ASCII-only**. Prove with PSParser (0 errors),
  and re-prove after any edit touching comments or strings.
- Display output is never evidence for byte claims: `???`/mojibake in a
  console transcript means "re-check with a byte read" (`python3 -c` over
  raw bytes), never "the file is damaged". A whole pipeline was once halted
  over console-rendering artifacts; the bytes were clean all along.
- When authoring tools mangle non-ASCII in transit, write `\uXXXX` escapes
  in generated scripts instead of literal characters.

## 2. Native stderr + `$ErrorActionPreference = "Stop"` = death on success

Git progress lines (`Cloning into...`, `To https://...`) arrive on stderr.
Under `Stop`, every one becomes a terminating error — the script dies on
screamingly successful output, before `$LASTEXITCODE` is ever read.

- Never set `Stop` around native calls with chatty stderr. Judge every
  native call by `$LASTEXITCODE` explicitly (normalize `$null` to 0, same
  as the `run.ps1` stages do).
- `$ErrorActionPreference` mismatches between scripts that call each other
  are a defect class of their own: state the contract (`$LASTEXITCODE`
  judging, no `Stop` near natives) wherever scripts invoke scripts.

## 3. Tee-Object writes UTF-16LE on Win-PS5.1; gh posts bytes raw

`opencode run ... | Tee-Object -FilePath report.md` produces a UTF-16LE file
(BOM `FF FE`) on Windows PowerShell 5.1. `gh issue comment --body-file`
posts those bytes verbatim, so GitHub stores a NUL after every character and
renders the comment as `D^@e^@l^@e^@t^@i^@n^@g^@` mojibake (paid 2026-10-07:
first comment on the hello_world removal issue arrived unreadable; byte read
showed the BOM plus hundreds of NULs, on both the file and the posted body).

- Convention: **sanitize every machine-captured report before posting** -
  BOM-aware decode, strip ANSI CSI/OSC escapes and stray NULs, rewrite UTF-8
  without BOM (explicit `[Text.UTF8Encoding]::new($false)`; `Out-File -Encoding
  utf8` still writes a BOM on 5.1). `Convert-ReportToUtf8` in
  `dispatcher/Invoke-Dispatch.ps1` owns this; no second sanitizer anywhere.
- Prove with a byte read (`FF FE` absent, `00` absent), never with console
  rendering: mojibake in a transcript means "check the posted bytes".

## 4. `powershell -File` coerces `4,5` to `45` for `[int[]]` params

With `powershell -File script.ps1 -IssueNumbers 4,5`, every trailing
argument arrives as a STRING, so `[int[]]` binds `"4,5"` as the single
number 45 (comma reads as a thousands separator) — the script then waits
on a nonexistent issue #45 instead of #4 and #5 (seen live 2026-10-07:
a closer DryRun printed `issue #45`). In-session calls (`& .\script.ps1
-IssueNumbers 4,5`) bind the array correctly and are the only supported
entry; from outside PowerShell, wrap with `-Command "& ..."`.

- Convention: **verify multi-issue sets in DryRun output before firing** -
if the numbers look joined, the invocation style is wrong, not the script.

## 5. Triple backtick before a closing double-quote swallows the file

In an expandable `"..."` string the backtick is the escape character, so
a fence pattern like `"(?ms)` + ```human-report...```" parses the final
backtick pair as literal-backtick plus escaped-quote: the string never
terminates and the rest of the file becomes string content (paid 2026-10-07:
the PSParser gate went red with cascading `Missing ')'` errors far downstream
of the real line, in code that read fine to the eye).

- Convention: **fence patterns live in single-quoted strings** -
  backticks are literal there, no escaping, parses exactly.
- The PSParser 0-errors gate is load-bearing for exactly this class: run it
  after every edit touching strings that contain backticks.
