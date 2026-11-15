# BZ-100 firmware: provenance and how to audit it

This repository is the company-controlled fork of AM32 used for the BZ-100 ESC. The `bz100/*`
branches carry the released firmware source. Everything needed to rebuild a release bit for bit is
in the repository.

| Item | Pin |
| --- | --- |
| Upstream | `https://github.com/am32-firmware/AM32` |
| Upstream release | v2.22, commit `3863f9dfd9132cc0f6d42dce5dede49faa72c8ca` |
| Change on top of upstream | one target block, `BLUEZONE_100A_L431_CAN`, in `Inc/targets.h` (first commit on `bz100/v2.22`); on branch `claude/reverse-spin-check`, a start-up reverse-spin check in `Src/main.c` (polling-mode zero crossings must follow the opposite comparator level) and a bus over-voltage brake stop (no synchronous rectification above 62 V, `Src/main.c`, `Mcu/l431/Src/phaseouts.c`, `BUS_OV_BRAKE_STOP` in the target block); on branch `claude/ov-cut-brake-stop`, synchronous rectification also stops the moment the board's over-voltage cut trips (rev C flag on PB5, polled at 20 kHz, low sides off at once, latched until the flag is low and the bus is below 60 V; `BUS_OV_CUT_PIN` in the target block, `Mcu/l431/Src/peripherals.c`) |
| Compiler | xPack GNU Arm Embedded GCC 10.3.1-2.3, archive SHA-256 `559dcf1c2dfddac513110fe23da0ef254032c09967eaa901f075515d51818719` (the compiler AM32's own `make arm_sdk_install` uses) |
| Build flags | AM32's Makefile unchanged; four path-mapping flags passed through `CC=` so that build paths do not enter the ELF (they do not change the flashable image) |
| Release hashes | `bz100/release-hashes.sha256` |
| Bootloader | AM32-bootloader v19.0.0 with one board block; built from the board repository (`firmware/build-bootloader.sh`) |

## Reproduce a build

```
git clone <this repository> && cd <clone>
git checkout bz100/v2.22
bz100/build-repro.sh
```

The script downloads the pinned compiler (checksum verified), exports the committed tree twice into
different directories, builds both, and passes only if `.bin`, `.hex` and `.elf` are identical between
the two and equal to `bz100/release-hashes.sha256`. The same script runs in CI on every push to a
`bz100/*` branch and publishes the hashes in the job summary.

## Releasing a change

1. Commit the source change on a `bz100/*` branch.
2. Run `bz100/build-repro.sh --update` and commit the new `bz100/release-hashes.sha256` in the same change.
3. Tag the commit. The tag, the hashes file and the CI run are the audit record.

## Software bill of materials and licences

The SPDX SBOM and the licence-obligations note are generated in the board repository
(`firmware/sbom/`, `firmware/LICENSE-OBLIGATIONS.md`). AM32 is GPL-3.0; this fork is the
corresponding source for every shipped image.
