#!/bin/bash

source /tmp/chroot-functions.sh

case ${clst_target} in
	livecd*|stage4)
		run_emerge --oneshot genkernel
		install -d /tmp/kerncache

		# Setup case structure for livecd_type
		case ${clst_livecd_type} in
			gentoo-release-minimal | gentoo-release-universal)
				case ${clst_hostarch} in
					amd64|x86)
						if [ -x /usr/share/genkernel/genkernel ]
						then
							gk=/usr/share/genkernel/genkernel
						else
							gk=/usr/bin/genkernel
						fi
						sed -i 's/initramfs_data.cpio.gz /initramfs_data.cpio.gz -r 1024x768 /' ${gk}
					;;
				esac
			;;
		esac
	;;

	netboot2)
		run_emerge --oneshot genkernel
		install -d /tmp/kerncache

		# Set the netboot builddate/hostname in linuxrc and copy to proper arch
		# directory in genkernel
		sed -e "s/@@MYDATE@@/$(date '+%Y%m%d')/g" \
		    -e "s/@@RELVER@@/${clst_version_stamp}/g" \
			/usr/share/genkernel/netboot/linuxrc.x \
			> /usr/share/genkernel/${clst_hostarch}/linuxrc

		echo ">>> Copying support files to ${clst_root_path} ..."
		cp -pPRf /usr/share/genkernel/netboot/misc/* \
			${clst_merge_path}

		echo ">>> Copying busybox config ..."
		cp -f /tmp/busy-config \
			/usr/share/genkernel/${clst_hostarch}/busy-config
	;;
esac
