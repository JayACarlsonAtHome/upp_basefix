# UPP: a pinned, patched U++ for each C++ standard

A version is a C++ standard, and every project builds its U++ windows with the U++ of its own
version:

| Version | Standard | Install (what projects use) |
|---------|----------|-----------------------------|
| [v001](v001/README.md) | C++23 | `v001/install/`: `umk`, the patched `uppsrc`, `GCC.bm` and `CLANG.bm` with `-std=c++23` |
| [v002](v002/README.md) | C++26 | `v002/install/`: the same with `-std=c++26` (and `-fcontracts` on a GCC with native contracts) |

Each version is a full copy (the script `upp_basefix.sh`, the pin, the patches, the checks and
the docs) and is built and checked at its own standard. Its work area (`work/`: the download, the
trees, its own umk) and its install (`install/`) stay inside it and are never committed.

    cd v001 && ./upp_basefix.sh bootstrap && ./upp_basefix.sh install    # U++ for C++23 projects
    cd v002 && ./upp_basefix.sh bootstrap && ./upp_basefix.sh install    # U++ for C++26 projects

The projects' `bsir.sh` scripts do this themselves: they clone this repository as `UPP` beside
them and install the version they need. The git repository is still named `upp_basefix` on GitLab
and GitHub.

Everything here is offered to the U++ project to use as it sees fit, under U++'s own license
model (BSD 2-Clause, `LICENSE`).
