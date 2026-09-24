# New Fedora compose or kernel

Moving the build to a new Fedora compose or a new Fedora kernel, and what a revision of the SP11 kernel means. The
rebase procedure and its known conflicts are in [`docs/kernel.md`](../kernel.md); the pins, caches and bump rules
in [`docs/pipeline.md`](../pipeline.md).

Edit `sp11.conf`: `FEDORA_COMPOSE` (from the ISO file name) in the `FEDORA_TARGET` branch you build and, for a new
Fedora kernel, `KERNEL_FEDORA_VERSION`, `KERNEL_FEDORA_RELEASE`, the source RPM's checksum in the
`KERNEL_SRPM_SHA256` case table and the checksum of Fedora's own `kernel-core` of that build in the
`KERNEL_STOCK_CORE_SHA256` case table (step 20 compares the configuration against it; both are on Koji:
`kojipkgs.fedoraproject.org/packages/kernel/`). Then run `FORCE=1 scripts/build-all.sh`. Checksum-pinned downloads
stay cached; the packages downloaded with dnf (`atheros-firmware`, the live-root dependencies, the sensors sources)
are cached per Fedora release and fetched again with `FORCE=1`. The ISO layout (volume id, marker file, kernel and
initrd paths, font, live menu) is read from each ISO. Other values a new release can touch, each of which stops the
build rather than guessing:

- a new kernel: the patch set has to be rebased onto its stable tag on a new branch of the kernel fork, and
  `KERNEL_PATCH_BASE_COMMIT` and `KERNEL_PATCH_COMMIT` set to the new commits (how, and the conflicts known for
  7.2.6 and 7.2.7, is in [`docs/kernel.md`](../kernel.md)), and a new symbol has to be set in `payload/kernel-local`
  (Fedora's configuration checks refuse an unset one);
- a new Fedora: `rpm/iio-sensor-proxy.spec.in`, a copy of Fedora's spec whose source is pinned by
  `IIO_SENSOR_PROXY_BASE_SPEC_SHA256` (refresh the template, then the pin), the package names in
  `LIVE_EXTRA_PKGS` and `SENSORS_DEPS_PKGS`, the dracut module names in `LIVE_DRACUT_OMIT`
  (`scripts/50-build-iso.sh`, Fedora 45's), the version floors in `rpm/sp11-sensors.spec.in`, and the UCM
  matcher patch in `scripts/30-build-support-rpm.sh`, which expects ooaklee's v19c `x1e80100.conf` matcher
  line.

`KERNEL_SP11_REV` (default 4) is everything the project changes in Fedora's kernel: the patch set's pinned commit
and `payload/kernel-local`. It becomes the buildid `.sp11.<revision>`, so the result is, for example,
`kernel-7.2.5-300.sp11.1.fc45` with the kernel version `7.2.5-300.sp11.1.fc45.aarch64`. The kernel packages are
install-only, and a rebuild with the same version would own the same `/boot` and module paths as the installed one,
so bump the revision with every change to the pinned commit or to `kernel-local`: `sp11.conf` pins each revision's
content (`KERNEL_SP11_REV_SHA256`: the revision number, `kernel-local`'s effective lines and the two pinned
commits), and step 20 stops when they and the revision disagree, printing the value for the new revision.
