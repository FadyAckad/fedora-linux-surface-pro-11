# New Fedora compose or kernel

Moving the build to a new Fedora compose or a new Fedora kernel, and what a revision of the SP11 kernel means. The
rebase procedure and the checks a rebase needs are in [`docs/kernel.md`](../kernel.md); the pins, caches and bump
rules in [`docs/pipeline.md`](../pipeline.md).

Edit `sp11.conf`: set `FEDORA_COMPOSE` (from the ISO file name) in the `FEDORA_TARGET` branch you build. For a new
Fedora kernel, set `KERNEL_FEDORA_VERSION`, `KERNEL_FEDORA_RELEASE`, the source RPM's checksum in the
`KERNEL_SRPM_SHA256` case table and the checksum of Fedora's own `kernel-core` of that build in the
`KERNEL_STOCK_CORE_SHA256` case table (step 20 compares the configuration against it); both are on Koji,
`kojipkgs.fedoraproject.org/packages/kernel/`. Then run `FORCE=1 scripts/build-all.sh`: checksum-pinned downloads
stay cached, the dnf downloads are fetched again, and the ISO layout is read from each ISO. Other values a new
release can touch, each of which stops the build rather than guessing:

- a new kernel: the patch set has to be rebased onto its stable tag on a new branch of the kernel fork, and
  `KERNEL_PATCH_BASE_COMMIT` and `KERNEL_PATCH_COMMIT` set to the new commits; how to do that, including a build
  from a local clone before the branch is pushed, is in [`docs/kernel.md`](../kernel.md). A new symbol has to be set
  in `payload/kernel-local`, because Fedora's configuration checks refuse an unset one;
- a new Fedora:
  - the iio-sensor-proxy source RPM of that release (`IIO_SENSOR_PROXY_SRPM` with its Koji URL and checksum).
    Koji's copies are unsigned, so check it against Fedora's signed copy first, as the kernel skill's
    [`reference.md`](../../.claude/skills/sp11-kernel-update/reference.md) does for the kernel's;
  - `rpm/iio-sensor-proxy.spec.in`, a copy of Fedora's spec whose source is pinned by
    `IIO_SENSOR_PROXY_BASE_SPEC_SHA256` (refresh the template, then the pin);
  - the package names in `LIVE_EXTRA_PKGS` and `SENSORS_DEPS_PKGS`;
  - the dracut module names in `LIVE_DRACUT_OMIT` (`scripts/50-build-iso.sh`, Fedora 45's);
  - the version floors in `rpm/sp11-sensors.spec.in`;
  - the UCM matcher patch in `scripts/30-build-support-rpm.sh`, which expects ooaklee's v19c `x1e80100.conf`
    matcher line.

`KERNEL_SP11_REV` (default 10) is everything the project changes in Fedora's kernel: the patch set's pinned commit
and `payload/kernel-local`. It becomes the buildid `.sp11.<revision>`, as in `kernel-7.2.5-300.sp11.1.fc45`. The
kernel packages are install-only, and a rebuild with the same version would own the same `/boot` and module paths
as the installed one, so bump the revision with every change to the pinned commit or to `kernel-local`. `sp11.conf`
pins each revision's content in `KERNEL_SP11_REV_SHA256` (the revision number, `kernel-local`'s effective lines and
the two pinned commits); step 20 stops when they and the revision disagree, and prints the value for the new
revision.
