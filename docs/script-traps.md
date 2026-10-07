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
