# Secure Boot on the installed system

Optional. The installer needs Secure Boot off, and an installed system works with it off. This guide switches
it on for the installed system: you sign a boot image for your kernel with a key of your own, enroll that key on
the Surface once, and the support RPM keeps GRUB's entries for it current. The facts behind every step:
[`docs/secure-boot.md`](../secure-boot.md).

## What it does and what it does not

- With Secure Boot on, the firmware starts only signed boot loaders, GRUB only your signed image, and the kernel
  refuses modules its build did not sign.
- The initramfs and the kernel's command line are not signed, as on any Fedora system. Secure Boot does not
  protect an unencrypted disk; an encrypted root can be opened by the tablet's TPM once Secure Boot is on
  (section 6).
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
sudo dnf install ./sp11-surface-support-3.19-1.fc45.aarch64.rpm ./sp11-kernel-secureboot-7.3.5-300.sp11.3.fc45.aarch64-1-1.fc45.aarch64.rpm
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

## 6. Open the encrypted root with the TPM, optional

For a root encrypted with LUKS2 ([`install.md`](install.md), step 5) and support 3.19 or later. A second key,
sealed in the TPM and bound to PCR 7 (the Secure Boot state and keys), opens the root at the start; the passphrase
stays as the fallback. PCR 7 does not cover the kernel's command line, so set a GRUB password first: it guards
GRUB's editor and command line, while Fedora's entries and the SP11 Windows entry start without it. GRUB asks for
the user `root` and this password, typed in the US layout:

```bash
sudo grub2-setpassword
```

Then, in a start through the signed entry (`status` reads `ACTIVE`), enroll the key; it asks for the disk's
passphrase:

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p5
```

It reports `New TPM2 token enrolled as key slot 1.`. `/dev/nvme0n1p5` is the tested unit's encrypted partition;
`lsblk -f` shows yours as `crypto_LUKS`. Tell the start to use the TPM, rebuild the initramfs and copy it for the
signed entry:

```bash
sudo sed -i '/^luks-/s/$/,tpm2-device=auto/' /etc/crypttab
```

```bash
sudo dracut -f
```

```bash
sudo /usr/libexec/sp11/sp11-secureboot sync
```

The next start opens the root without a prompt (1.3 s on the tested unit). The passphrase opens it instead when
PCR 7 differs, with Secure Boot off or after its keys changed (a Windows update of the revocation list among
them), and after the TPM was cleared in Windows. After a key change or a cleared TPM, enroll the key anew in a
start through the signed entry; the same command removes the old one:

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p5
```

What stays open: someone with the tablet who replaces the unsigned initramfs copy on the EFI partition
([`docs/secure-boot.md`](../secure-boot.md), What it protects).

## GRUB's menu while Secure Boot is on

GRUB loads no font file from the disk then, so the support RPM (3.15 or later) draws the menu's text as images.
The menu looks like the usual one, with a blue bar on the highlighted entry and a bar that fills while the ten
seconds count down. It lists the kernels that have a signed image, Windows and the firmware settings. Escape
leaves it for a text menu in small text; with a GRUB password (section 6) GRUB first asks for the user `root` and
that password, and shows the graphical menu again if it does not accept them. GRUB's editor and command line are
in small text as well.

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

With Secure Boot off the TPM key no longer matches, and the passphrase opens the root. To remove the key, the
`crypttab` option and the GRUB password:

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme0n1p5
```

```bash
sudo sed -i '/^luks-/s/,tpm2-device=auto$//' /etc/crypttab
```

```bash
sudo dracut -f
```

```bash
sudo rm /boot/grub2/user.cfg
```
