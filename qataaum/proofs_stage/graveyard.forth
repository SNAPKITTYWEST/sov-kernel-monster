\ GRAVEYARD MAP — SNAPKITTYWEST/SNAPKITTY-PROOFS
\ 1 repos | rendered by AHMAD-BOT + Forth renderer
\ The graveyard in Forth. Every repo is a word.

\ ── SNAPKITTY-PROOFS (gravity: 0.2, status: orphan) ──
: crawl-snapkitty-proofs ( -- )
  0.2 gravity
  dup alive? IF
    ." SNAPKITTY-PROOFS alive " cr
  ELSE dup broken? IF
    ." SNAPKITTY-PROOFS broken " cr
    "SNAPKITTY-PROOFS" repair
  ELSE
    ." SNAPKITTY-PROOFS orphan " cr
    "SNAPKITTY-PROOFS" flag
  THEN THEN
  drop
;

: crawl-graveyard ( -- )
  ." === SNAPKITTYWEST/SNAPKITTY-PROOFS GRAVEYARD CRAWL ===" cr
  crawl-snapkitty-proofs
  ." === CRAWL COMPLETE ===" cr
;

crawl-graveyard