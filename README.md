# RidgeKey — Goodix 533c for macOS (experimental)

An unofficial source integration of RidgeKey with the **Goodix 27c6:533c / GM168SEC**
host-matching Milan backend. Version **1.0.5331**, based on the commits in
[UPSTREAM.json](UPSTREAM.json). All build fixes are already included; no hotfix ZIPs needed.

## Tested hardware and status

One Dell XPS 9500, Intel x86_64, macOS Tahoe (reported 26.7.1), firmware 13016
and a previously provisioned zero PSK. The device owner reported successful native
build/installation, enrollment, verification, persistence after restarting the daemon,
rejection of the tested unregistered fingers, and lock-screen unlocking.
These are manual single-device results, not an independent security audit or a measured
false-accept/false-reject rate. A full reboot persistence test has not been separately recorded.
Other readers, firmware versions and macOS versions are untested.

This is **not native Apple Touch ID**. Unlock uses RidgeKey's existing agent to enter
a locally stored account password after identification. It does not implement Secure
Enclave, Apple Pay or FileVault preboot authentication. Admin authorization is disabled
in this integration. Do not enable the bundled upstream sudo/admin integration tools.

## What changed

- Full upstream Goodix53x5 Milan backend, with only USB ID 27c6:533c registered.
- Host template storage; unsupported on-sensor template deletion is avoided.
- Templates and preprocessing state stored in root-only System Keychain items;
  .print files contain markers, not serialized fingerprints.
- Adaptive template updates saved before returning successful identification.
- Offline core, synthetic Milan/runtime/transport and storage tests in the build.
- Synthetic Keychain preflight uses separate writer/reader processes and checks
  that direct access by an ordinary user is denied.
- Private dependency prefix/build fixes, GNU C11, and strict agent signature checks
  using the actual CS_RUNTIME bit. Finish-Build.command can resume packaging.
- Screen unlocking is gated off until Enable-Unlock.command is explicitly run.

## Build and install

Use an **Intel Mac/Hackintosh** with Xcode Command Line Tools, Python 3, network
access and several GB free. Apple Silicon is not a supported target of these scripts.
Clone/extract onto the internal disk, open Terminal in this repository, then:

```bash
xcode-select -p
bash Check-Keychain.command
bash Build.command
```

If CLT is absent, run `xcode-select --install` first. Build downloads dependencies into
`~/Library/Caches/XPS-RidgeKey-533c-lab1` and uses a private Python venv; no Homebrew.
Wait for **BUILD_COMPLETE**, then:

```bash
bash Install-Test.command
```

The scripts request sudo locally where needed. Do not run the top-level commands with sudo.
Installation puts the service in `/usr/local/ridgekey` and the app in `/Applications`.
Only one program may hold the fingerprint sensor; stop older Goodix experiments first.
Keep fingers off the sensor during initial calibration, then enroll in RidgeKey.app.
No EFI/NVRAM change, sensor reset, firmware flash or PSK provisioning is performed.
This is not a setup utility for a factory-state or Windows-provisioned sensor.

If **RidgeKey 1.0.0** is already installed, read [migration instructions](docs/MIGRATION.md).
The installer intentionally blocks unreviewed replacement of another RidgeKey version.

## Verify, then opt into screen unlocking

```bash
bash Verify-Persistence.command
/usr/local/bin/ridgekeyctl verify -t 45
```

Repeat with the registered finger and several unregistered fingers. Do not enable
unlock if unregistered fingers are accepted. Passing a few trials is not an accuracy estimate.
When satisfied:

```bash
bash Enable-Unlock.command
```

Enter the account password only in the local prompt, grant RidgeKey Agent Accessibility,
then lock with Control-Command-Q and test. To turn this off while keeping enrolled fingers:

```bash
bash Disable-Unlock.command
```

Normal password login remains available. Keychain protects stored data, but biometric
material passes through root-process RAM; this does not protect against a compromised root/kernel.

## Development, review and releases

- Integrated buildable source: Source/. Upstream documentation there is retained for attribution;
  this root README describes the 533c build and takes precedence for its supported features.
- Reviewable patches against pinned upstream: patches/; reproduction: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
- `python3 tools/verify-source.py` checks the shipped snapshot. SHA256SUMS is an integrity
  manifest, not a cryptographic signature or publisher identity.
- `bash Finish-Build.command` finishes a cached bundle after a signing/packaging failure.
- `bash Export-Release.command` packages a verified cached bundle on the Dell into Releases/;
  attach the source ZIP/repository revision with any binary release.
- No prebuilt executable is included in this source repository. Check-Keychain.command
  compiles its two synthetic tools locally with CLT; they can also be rebuilt with
  `bash tools/rebuild-keychain-tools.sh`.

Build/diagnostic reports are local and ignored by Git. Review reports before sharing;
do not upload templates, fingerprint captures, passwords, Keychains or signing keys.
See [README-VI.md](README-VI.md), [licensing](LICENSE.md) and [validation notes](docs/VALIDATION.md).

## Credits

Konstantinos (labrouss) for RidgeKey; nikicat and the Goodix53x5 contributors for the
backend; Berkekbgz for native matcher research; AndyHazz and goodix-fp-linux-dev for
earlier protocol work; libfprint and its contributors. This project is not an official
RidgeKey release and does not imply upstream endorsement.
