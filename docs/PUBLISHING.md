# Publishing this source on GitHub

Create an empty repository on GitHub. From this source directory on macOS:

```bash
python3 tools/verify-source.py
git init
git add .
git diff --cached --stat
git commit -m "Add experimental RidgeKey Goodix 533c macOS integration"
git branch -M main
```

Set the remote to your own empty repository, then push main using your normal
GitHub authentication. Keep the upstream credits, commit pins and licenses.
Use a description such as “Experimental Goodix 27c6:533c support for RidgeKey on macOS”.
Do not describe it as official RidgeKey, Apple Touch ID or a universal Goodix driver.

For a release, the source archive can be regenerated with:

```bash
python3 tools/package-source.py
```

On the Dell that completed the native build, optionally run:

```bash
bash Export-Release.command
```

Attach the binary tar.gz and SHA256 file under Releases/<timestamp>/ together with
the corresponding source archive and a link to the exact source commit. Release
notes should describe the tested machine and experimental limitations from README.
The binary export is not a notarized installer and has not been independently
validated after redistribution. The documented installation path is source build
followed by Install-Test.command. Do not attach the installed application-support
directory, logs, fingerprint records or Keychain databases.
