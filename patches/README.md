# Reference patches

These patches preserve small, evidence-backed changes against pinned upstream research baselines. They are not applied automatically and do not turn the reference port into the final Bellpad architecture.

`pc-port/0001-handle-aligned-read-tail.patch` applies to `birabittoh/ACGC-PC-Port` commit `915fb86ba9a6c2144dabda9143d93af7a3f92be7`:

```sh
git -C ref/upstream/acgc-64bit apply --unidiff-zero \
  ../../../patches/pc-port/0001-handle-aligned-read-tail.patch
```

The affected `pc/` compatibility-layer code is MIT-licensed by that upstream. The patch contains no game data.
