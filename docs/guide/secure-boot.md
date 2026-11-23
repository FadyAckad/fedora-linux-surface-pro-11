# Secure Boot on the installed system

Optional. The installer needs Secure Boot off, and an installed system works with it off. This guide switches
it on for the installed system: you sign a boot image for your kernel with a key of your own, enroll that key on
the Surface once, and the support RPM keeps GRUB's entries for it current. The facts behind every step:
[`docs/secure-boot.md`](../secure-boot.md).

## What it does and what it does not

- With Secure Boot on, the firmware starts only signed boot loaders, GRUB only your signed image, and the kernel
  refuses modules its build did not sign.
- The initramfs and the kernel's command line are not signed, as on any Fedora system. Fedora has the tablet's
  TPM from kernel 7.3.5 revision 2, but nothing binds a disk key to it: Secure Boot does not protect an
  unencrypted disk and does not unlock an encrypted one by itself.
- Fedora's own boot entries start no kernel on this tablet while Secure Boot is on. A kernel without a signed
  image, an older one for instance, needs Secure Boot off.
- If an update of Fedora's boot loaders ever breaks the route, switching Secure Boot off in the UEFI brings the
  usual start back.

## 1. The signing key, once, in WSL

The key goes into `sp11-secureboot/` of your checkout, which `.gitignore` keeps out of git, and the pipeline reads
it only to sign. Whoever holds it can sign an image your Surface accepts, so it is kept encrypted with a
passphrase of your choice. Run the commands in the checkout.

```bash
mkdir -m 700 sp11-secureboot
```

The first command creates the key and asks twice for the passphrase; the key is never written unencrypted.

```bash
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 | openssl pkcs8 -topk8 -scrypt -out sp11-secureboot/sp11-mok.key
```

The second makes the certificate from it and asks for the passphrase once.

```bash
openssl req -new -x509 -key sp11-secureboot/sp11-mok.key -days 3650 -subj "/CN=Surface Pro 11 Secure Boot/" -addext "basicConstraints=critical,CA:TRUE" -addext "extendedKeyUsage=codeSigning" -out sp11-secureboot/sp11-mok.crt
```

Keep the passphrase in your password manager and a copy of both files somewhere outside this PC: without the
passphrase the key file is of no use to anyone. Another directory works when `SECUREBOOT_KEY_DIR` in `sp11.conf`
names it.

## 2. Build the signed image

With the key in place, `scripts/build-all.sh` builds the image after the kernel and asks for the key's passphrase
when it signs. Alone, for a kernel that is already built:

```bash
scripts/25-build-secureboot-rpms.sh
```

The result is `build/rpms/sp11-kernel-secureboot-<kernel version>-1-1.fc45.aarch64.rpm`: the signed image for
exactly that kernel build, with your certificate beside it. The check of the package together with the support
RPM, in a copy of the live root:

```bash
scripts/26-verify-secureboot-rpms.sh
```

## 3. Install on the Surface

Copy the support RPM (3.12 or later) and the image's RPM to Fedora and install them, with Secure Boot still off:

```bash
sudo dnf install ./sp11-surface-support-3.18-1.fc45.aarch64.rpm ./sp11-kernel-secureboot-7.3.5-300.sp11.3.fc45.aarch64-1-1.fc45.aarch64.rpm
```

```bash
sudo /usr/libexec/sp11/sp11-secureboot status
```

The last line reads `RESULT: NOT READY: the key is not enrolled` until step 4 is done, then `RESULT: READY: with
Secure Boot on, the Surface starts through the signed entries`.

## 4. Enroll the key, once

The certificate came with the package. The command asks twice for a password of your choice, which the next
start asks for once; shim's key manager uses the US keyboard layout.

```bash
sudo mokutil --import /usr/lib/modules/$(uname -r)/sp11-secureboot.der
```

```bash
sudo systemctl reboot
```

A blue screen, `Shim UEFI key management`, counts down ten seconds. Press a key, choose `Enroll MOK`, `Continue`
and `Yes`, type the password and choose `Reboot`.

## 5. Switch Secure Boot on

Hold Volume Up, press and release Power, and let go of Volume Up when the Surface UEFI shows. Under `Security`,
`Secure Boot`, choose `Change configuration`, select `Microsoft & 3rd party CA`, confirm, then `Exit` and
`Restart now`. Fedora starts by itself through the signed entry. If it does not, switch Secure Boot off again
(The way back, below) and look at the status. After the login:

```bash
sudo /usr/libexec/sp11/sp11-secureboot status
```

The last line reads `RESULT: ACTIVE: this boot came through a signed entry with Secure Boot on`.

## GRUB's menu while Secure Boot is on

GRUB loads no font file from the disk then, so the support RPM (3.15 or later) draws the menu's text as images.
The menu looks like the usual one, with a blue bar on the highlighted entry and a bar that fills while the ten
seconds count down. It lists the kernels that have a signed image, Windows and the firmware settings. Escape
leaves it for a text menu in small text; GRUB's editor and command line are in small text as well.

The status names the menu in place:

```bash
sudo /usr/libexec/sp11/sp11-secureboot status
```

Its `menu:` line reads `graphical while Secure Boot is on`. If it reads `a text menu while Secure Boot is on`, the
images could not be drawn, and a sync says why:

```bash
sudo /usr/libexec/sp11/sp11-secureboot sync
```

## Kernel updates

Every kernel build needs its own signed image. Build it with step 25 after the kernel (it asks for the key's
passphrase) and install it in the same
command as the kernel packages ([`update.md`](update.md), Kernel). A kernel installed without its image is not
offered while Secure Boot is on: GRUB starts the newest kernel that has one, and `status` names the kernel
without.

## The way back

In the Surface UEFI, under `Security`, `Secure Boot`, `Change configuration`, select `None`. The usual entry
starts after it. To take a signed image off as well, remove its package; its copies on the ESP and its menu
entry go with it:

```bash
sudo dnf remove sp11-kernel-secureboot-7.3.5-300.sp11.3.fc45.aarch64
```

The enrolled key stays in shim's list.
