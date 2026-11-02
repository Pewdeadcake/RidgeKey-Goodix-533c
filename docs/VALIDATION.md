# Validation record

## Device-owner observations (2026-11-02)

Dell XPS 9500 / 27c6:533c / Intel macOS Tahoe. Owner confirmed successful build,
installation and enrollment, then reported that all requested checks worked:
verification, persistence across daemon restart, rejection of tested unregistered
fingers, and lock-screen unlocking. Trial counts and complete error-rate measurements
were not recorded. Full-machine reboot persistence was not separately established.
No user logs or biometric data are included here.

## Build and integration checks

The native build reached the offline core/Milan tests and app/bundle assembly before
a shell signature-check failure. The check was changed to capture codesign output
fully and test numeric CS_RUNTIME while retaining strict signature verification.
The owner subsequently reported successful installation and operation.

Local mocked tests reproduced the old pipefail/SIGPIPE (141), tested valid/invalid/
missing runtime signatures and exercised the actual resume branch without recompilation.
Those mocks do not replace macOS code-signing or sensor tests. The Keychain preflight
was also reported passing on the Dell with a separate root reader and ordinary-user denial.

This repository does not certify biometric strength, spoof resistance, Windows recovery,
all macOS versions, or other Goodix devices. The scripts never provision sensor firmware
or PSK. In-memory processing remains within the host trust boundary.
