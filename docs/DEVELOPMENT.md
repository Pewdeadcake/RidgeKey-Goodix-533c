# Source layout and upstream review

Source/RidgeKey and Source/libfprint contain the integrated source. Source/goodix533c
is the upstream Goodix source and tests retained with their notices. Goodix numerical
Milan implementation/thresholds were not tuned for this device.

To reproduce source modifications, obtain clean checkouts at the commits in UPSTREAM.json:

```bash
git -C /path/to/pristine-RidgeKey apply /path/to/this-repo/patches/RidgeKey.patch
git -C /path/to/pristine-libfprint apply /path/to/this-repo/patches/libfprint.patch
git -C /path/to/pristine-goodix533c apply /path/to/this-repo/patches/goodix533c.patch
```

The libfprint patch already includes selected macOS portability patches, the three
Goodix libfprint patches, integrated driver/tests, 533c-only registration and Keychain
adaptation. Do not apply upstream integration patches a second time. Keep the
Source sibling layout and Source/build-goodix-deps.sh for the build script.

The patches include complete added source, not merely references to external files.
The goodix533c patch only normalizes line endings in the retained upstream tree.
To review integration changes first, inspect RidgeKey.patch and daemon/store.c,
daemon/bio-keychain.c, daemon/ridgekeyd.c, daemon/secret.c and the private identify API.

Build.command runs the offline tests; genuine and impostor finger trials require
manual device testing. Source/ includes upstream tests/fixtures, not the owner's captures.
The two synthetic Keychain tools are compiled locally on Intel macOS using
tools/rebuild-keychain-tools.sh. After intentional edits, review them and regenerate
SHA256SUMS with tools/update-manifest.py; then tools/verify-source.py.

Root scripts use the existing lab1 cache so current users can export their working
bundle without rebuilding. Start from a separate cache/user environment for a clean
build comparison. The snapshot is not a bit-for-bit reproducible binary build claim;
some dependency tags and toolchain inputs are resolved by the inherited build scripts.
