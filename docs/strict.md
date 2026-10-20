# Strict builds (-Wall -Wextra)

U++'s own build methods use neither `-Wall` nor `-Wextra`, and its clang methods turn
`-Wlogical-op-parentheses` off (uppsrc/ide/Builders/Install.cpp): the U++ authors write
some things on purpose that strict warnings flag. A strict build of the check programs
gives about 1,500 unique U++ warnings with gcc and 950 with clang. upp_basefix.sh splits
them:

- **ours**: warnings in upp_basefix's own code. Must be 0.
- **U++**: any U++ warning not listed below. Must be 0: a new one turns the GUI row
  yellow and is either a bug to patch (as 0009 and 0010 were) or a site to review.
- **U++ house style**: counted apart, not a failure:
  - these kinds anywhere: `-Wunused-parameter` (virtuals and callbacks that ignore an
    argument), `-Wdeprecated-copy` (classes with a user copy constructor and an implicit
    assignment), `&&` within `||` without parentheses (U++ precedence style);
  - the sites in `supp/strict-reviewed.txt`, each read by hand, grouped by kind with the
    reason it is not a bug (fall-throughs, signed/unsigned compares of character codes,
    aggregate tables, CHECK in release builds, ...).

The list is for the pinned tree (18619 + patches 0001-0010); a new pin needs a new review.

Warnings are counted from one file per compile (the build method runs the compiler
through `$WORK/bin/<compiler>-cc`, which keeps its messages in `$WORK/diag/`): umk's log
interleaves the lines of parallel compiles, so counting it splits some warnings.
Only files compiled in a run print warnings: tick Clean for the whole tree's count.
