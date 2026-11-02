# Moving from stock RidgeKey 1.0.0

The lab installer deliberately blocks an existing installation whose BUILDINFO does
not identify version 1.0.5331. Do not edit BUILDINFO merely to bypass that check.

After completing this source build, inspect the current installation:

```bash
cat /usr/local/ridgekey/BUILDINFO.txt
/usr/local/ridgekey/bin/ridgekeyd --version
```

For the stock 1.0.0 installation tested during this project, its normal uninstall
path restores enabled sudo/admin integration before removing binaries. Use the
reviewed uninstaller in the built bundle, **without --purge**:

```bash
sudo /bin/bash "$HOME/Library/Caches/XPS-RidgeKey-533c-lab1/bundle/ridgekey-1.0.5331-macos-x86_64/uninstall.sh"
```

Wait for successful completion, then run `bash Install-Test.command` from this repo.
Normal uninstall keeps print records and stored passwords; it does not reset the
sensor. Old stock/experimental records are not automatically imported as native Milan
templates. Enroll once in the new app as needed. If uninstall reports an error, resolve
it before proceeding; do not manually delete PAM modules or authorization plugins.

For an unknown/different RidgeKey installation, review its migration requirements first.
To later uninstall this integration, the same normal command keeps data; --purge is
an explicit destructive operation and is not part of installation or migration.
