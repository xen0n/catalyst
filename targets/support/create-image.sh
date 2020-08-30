#!/bin/bash

source ${clst_shdir}/support/functions.sh
source ${clst_shdir}/support/filesystem-functions.sh

## START RUNSCRIPT

# WORK IN PROGRESS

# This script takes a filesystem tree created by catalyst and converts it
# into a readily bootable disk image for use with QEMU, cloud services, etc.
# Things that should be configurable when it's finished:
#   * image type (raw, qcow2, vmdk)
#   * disk size
#   * system partition size? filesystem?
#   * create a blank swap partition? size?
#   * boot loader and partition type (mbr&dos, or uefi&gpt; other combos 
#     not supported)
#   * start sshd?
#   * root password or (much better) root authorized_keys
#
# For now support is limited to arches where cloud services exist (i.e., 
# amd64 and arm64).

# Check for our bootable disk image creation tools
# case ${clst_hostarch} in
# 	*)
# 		cdmaker="mkisofs"
# 		cdmakerpkg="app-cdr/cdrkit or app-cdr/cdrtools"
# 		;;
# esac

# [ ! -f /usr/bin/${cdmaker} ] \
#    && echo && echo && die \
#    "!!! /usr/bin/${cdmaker} is not found.  Have you merged ${cdmakerpkg}?" \
#    && echo && echo

# If not volume ID is set, make up a sensible default
if [ -z "${clst_image_volume_id}" ]
then
	case ${clst_image_type} in
		gentoo-*)
			case ${clst_hostarch} in
				amd64)
					clst_image_volume_id="Gentoo Linux - AMD64"
				;;
				arm64)
					clst_image_volume_id="Gentoo Linux - ARM64"
				;;
				*)
					clst_image_volume_id="Gentoo Linux"
				;;
				esac
	esac
fi

if [ "${#clst_image_volume_id}" -gt 32 ]; then
	old_clst_image_volume_id=${clst_image_volume_id}
	clst_image_volume_id="${clst_image_volume_id:0:32}"
	echo "ISO Volume label is too long, truncating to 32 characters" 1>&2
	echo "old: '${old_clst_image_volume_id}'" 1>&2
	echo "new: '${clst_image_volume_id}'" 1>&2
fi

if [ "${clst_fstype}" == "zisofs" ]
then
	mkisofs_zisofs_opts="-z"
else
	mkisofs_zisofs_opts=""
fi

#we want to create a checksum for every file on the iso so we can verify it
#from genkernel during boot.  Here we make a function to create the sha512sums, and blake2sums
isoroot_checksum() {
	echo "Creating checksums for all files included in the iso, please wait..."
	if [ -z "${1}" ] || [ "${1}" = "sha512" ]; then
		find "${clst_target_path}" -type f ! -name 'isoroot_checksums' ! -name 'isolinux.bin' ! -name 'isoroot_b2sums' -exec sha512sum {} + > "${clst_target_path}"/isoroot_checksums
		${clst_sed} -i "s#${clst_target_path}/\?##" "${clst_target_path}"/isoroot_checksums
	fi
	if [ -z "${1}" ] || [ "${1}" = "blake2" ]; then
		find "${clst_target_path}" -type f ! -name 'isoroot_checksums' ! -name 'isolinux.bin' ! -name 'isoroot_b2sums' -exec b2sum {} + > "${clst_target_path}"/isoroot_b2sums
		${clst_sed} -i "s#${clst_target_path}/\?##" "${clst_target_path}"/isoroot_b2sums
	fi
}

run_mkisofs() {
	if [ -n "${clst_livecd_verify}" ]; then
		if [ "${clst_livecd_verify}" = "sha512" ]; then
			isoroot_checksum sha512
		elif [ "${clst_livecd_verify}" = "blake2" ]; then
			isoroot_checksum blake2
		else
			isoroot_checksum
		fi
	fi
	echo "Running \"mkisofs ${@}\""
	mkisofs "${@}" || die "Cannot make ISO image"
}

# Here we actually create the ISO images for each architecture
case ${clst_hostarch} in
	x86|amd64)
		# detect if an EFI bootloader is desired
		if 	[ -d "${clst_target_path}/boot/efi" ] || \
			[ -d "${clst_target_path}/boot/EFI" ] || \
			[ -e "${clst_target_path}/gentoo.efimg" ]
		then
			if [ -e "${clst_target_path}/gentoo.efimg" ]
			then
				echo "Found prepared EFI boot image at \
					${clst_target_path}/gentoo.efimg"
			else
				echo "Preparing EFI boot image"
				if [ -d "${clst_target_path}/boot/efi" ] && [ ! -d "${clst_target_path}/boot/EFI" ]; then
					echo "Moving /boot/efi to /boot/EFI"
					mv "${clst_target_path}/boot/efi" "${clst_target_path}/boot/EFI"
				fi
				# prepare gentoo.efimg from clst_target_path /boot/EFI dir
				iaSizeTemp=$(du -sk --apparent-size "${clst_target_path}/boot/EFI" 2>/dev/null)
				iaSizeB=$(echo ${iaSizeTemp} | cut '-d ' -f1)
				iaSize=$((${iaSizeB}+64)) # add slack, tested near minimum for overhead
				echo "Creating loopback file of size ${iaSize}kB"
				dd if=/dev/zero of="${clst_target_path}/gentoo.efimg" bs=1k \
					count=${iaSize}
				echo "Formatting loopback file with FAT16 FS"
				mkfs.vfat -F 16 -n GENTOOLIVE "${clst_target_path}/gentoo.efimg"

				mkdir "${clst_target_path}/gentoo.efimg.mountPoint"
				echo "Mounting FAT16 loopback file"
				mount -t vfat -o loop "${clst_target_path}/gentoo.efimg" \
					"${clst_target_path}/gentoo.efimg.mountPoint" || die "Failed to mount EFI image file"

				echo "Populating EFI image file from ${clst_target_path}/boot/EFI"
				cp -rv "${clst_target_path}"/boot/EFI/ \
					"${clst_target_path}/gentoo.efimg.mountPoint" || die "Failed to populate EFI image file"

				umount "${clst_target_path}/gentoo.efimg.mountPoint"
				rmdir "${clst_target_path}/gentoo.efimg.mountPoint"

				echo "Copying /boot/EFI to /EFI for rufus compatability"
				cp -rv "${clst_target_path}"/boot/EFI/ "${clst_target_path}"
			fi
		fi

		if [ -e "${clst_target_path}/isolinux/isolinux.bin" ]; then
			echo '** Found ISOLINUX bootloader'
			if [ -e "${clst_target_path}/gentoo.efimg" ]; then
			  # have BIOS isolinux, plus an EFI loader image
			  echo '** Found GRUB2 EFI bootloader'
				echo 'Creating ISO using both ISOLINUX and EFI bootloader'
				run_mkisofs -J -R -l ${mkisofs_zisofs_opts} -V "${clst_iso_volume_id}" -o "${1}" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -eltorito-platform efi -b gentoo.efimg -no-emul-boot -z "${clst_target_path}"/
				isohybrid --uefi "${1}"
		  else
			  echo 'Creating ISO using ISOLINUX bootloader'
			  run_mkisofs -J -R -l ${mkisofs_zisofs_opts} -V "${clst_iso_volume_id}" -o "${1}" -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table "${clst_target_path}"/
			  isohybrid "${1}"
		  fi
		elif [ -e "${clst_target_path}/gentoo.efimg" ]; then
			echo '** Found GRUB2 EFI bootloader'
			echo 'Creating ISO using EFI bootloader'
			run_mkisofs -J -R -l ${mkisofs_zisofs_opts} -V "${clst_iso_volume_id}" -o "${1}" -b gentoo.efimg -c boot.cat -no-emul-boot "${clst_target_path}"/
		else
			echo '** Found no known bootloader'
			echo 'Creating ISO with fingers crossed that you know what you are doing...'
			run_mkisofs -J -R -l ${mkisofs_zisofs_opts} -V "${clst_iso_volume_id}" -o "${1}" "${clst_target_path}"/
		fi
	;;
esac
exit  $?
