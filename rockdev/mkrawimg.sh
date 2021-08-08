#!/bin/bash

RAWIMG=Image/raw.img
echo "Generate raw image : ${RAWIMG} !"

LOADER1_START=64
PARAMETER=$(cat package-file | grep -wi parameter | awk '{printf $2}' | sed 's/\r//g')

PARTITIONS=()
START_OF_PARTITION=0
PARTITION_INDEX=0

rm -rf ${RAWIMG}

ALIGN()
{
	X=$1
	A=$2
	OUT=$(($((${X} + ${A} -1 ))&$((~$((${A}-1))))))
	printf 0x%x ${OUT}
}

ROOTFS_LAST=$(grep "rootfs:grow" Image/parameter.txt)
if [ -z "${ROOTFS_LAST}" ]
then
echo "Resize rootfs partition size"
FILE_P=$(readlink -f Image/rootfs.img)
FS_INFO=$(dumpe2fs -h ${FILE_P})
BLOCK_COUNT=$(echo "${FS_INFO}" | grep "^Block count" | cut -d ":" -f 2 | tr -d "[:blank:]")
INODE_COUNT=$(echo "${FS_INFO}" | grep "^Inode count" | cut -d ":" -f 2 | tr -d "[:blank:]")
BLOCK_SIZE=$(echo "${FS_INFO}" | grep "^Block size" | cut -d ":" -f 2 | tr -d "[:blank:]")
INODE_SIZE=$(echo "${FS_INFO}" | grep "^Inode size" | cut -d ":" -f 2 | tr -d "[:blank:]")
BLOCK_SIZE_IN_S=$((${BLOCK_SIZE}>>9))
INODE_SIZE_IN_S=$((${INODE_SIZE}>>9))
SKIP_BLOCK=70
EXTRA_SIZE=$(expr 50 \* 1024 \* 2 ) #50M

FSIZE=$(expr ${BLOCK_COUNT} \* ${BLOCK_SIZE_IN_S} + ${INODE_COUNT} \* ${INODE_SIZE_IN_S} + ${EXTRA_SIZE} + ${SKIP_BLOCK})
PSIZE=$(ALIGN $((${FSIZE})) 512)
PARA_FILE=$(readlink -f Image/parameter.txt)

ORIGIN=$(grep -Eo "0x[0-9a-fA-F]*@0x[0-9a-fA-F]*\(rootfs" $PARA_FILE)
NEWSTR=$(echo $ORIGIN | sed "s/.*@/${PSIZE}@/g")
OFFSET=$(echo $NEWSTR | grep -Eo "@0x[0-9a-fA-F]*" | cut -f 2 -d "@")
NEXT_START=$(printf 0x%x $(($PSIZE + $OFFSET)))
sed -i.orig "s/$ORIGIN/$NEWSTR/g" $PARA_FILE
sed -i "/^CMDLINE.*/s/-@0x[0-9a-fA-F]*/-@$NEXT_START/g" $PARA_FILE
fi

for PARTITION in `cat ${PARAMETER} | grep '^CMDLINE' | sed 's/ //g' | sed 's/.*:\(0x.*[^)])\).*/\1/' | sed 's/,/ /g'`; do
        PARTITION_NAME=`echo ${PARTITION} | sed 's/\(.*\)(\(.*\))/\2/' | cut -f 1 -d ":"`
        PARTITION_START=`echo ${PARTITION} | sed 's/.*@\(.*\)(.*)/\1/'`
        PARTITION_LENGTH=`echo ${PARTITION} | sed 's/\(.*\)@.*/\1/'`

        PARTITIONS+=("$PARTITION_NAME")
        PARTITION_INDEX=$(expr $PARTITION_INDEX + 1)

        eval "${PARTITION_NAME}_START_PARTITION=${PARTITION_START}"
        eval "${PARTITION_NAME}_LENGTH_PARTITION=${PARTITION_LENGTH}"
        eval "${PARTITION_NAME}_INDEX_PARTITION=${PARTITION_INDEX}"
done

LAST_PARTITION_IMG=$(cat package-file | grep -wi $PARTITION_NAME | awk '{printf $2}' | sed 's/\r//g')

if [[ -f ${LAST_PARTITION_IMG} ]]; then
	IMG_ROOTFS_SIZE=$(stat -L --format="%s" ${LAST_PARTITION_IMG})
else
	IMG_ROOTFS_SIZE=0
fi

GPTIMG_MIN_SIZE=$(expr $IMG_ROOTFS_SIZE + \( $(((${PARTITION_START} + 0x2000))) \) \* 512)
GPT_IMAGE_SIZE=$(expr $GPTIMG_MIN_SIZE \/ 1024 \/ 1024 + 2)

dd if=/dev/zero of=${RAWIMG} bs=1M count=0 seek=$GPT_IMAGE_SIZE
parted -s ${RAWIMG} mklabel gpt

for PARTITION in ${PARTITIONS[@]}; do
    PSTART=${PARTITION}_START_PARTITION
    PLENGTH=${PARTITION}_LENGTH_PARTITION
    PINDEX=${PARTITION}_INDEX_PARTITION
    PSTART=${!PSTART}
    PLENGTH=${!PLENGTH}
    PINDEX=${!PINDEX}

    if [ "${PLENGTH}" == "-" ]; then
        echo "EXPAND"
        parted -s ${RAWIMG} -- unit s mkpart ${PARTITION} $(((${PSTART} + 0x00))) -34s
    else
        PEND=$(((${PSTART} + 0x00 + ${PLENGTH})))
        parted -s ${RAWIMG} unit s mkpart ${PARTITION} $(((${PSTART} + 0x00))) $(expr ${PEND} - 1)
    fi
done

UUID=$(cat ${PARAMETER} | grep 'uuid' | cut -f 2 -d "=")
VOL=$(cat ${PARAMETER} | grep 'uuid' | cut -f 1 -d "=" | cut -f 2 -d ":")
VOLINDEX=${VOL}_INDEX_PARTITION
VOLINDEX=${!VOLINDEX}

gdisk ${RAWIMG} <<EOF
x
c
${VOLINDEX}
${UUID}
w
y
EOF

if [ "$RK_IDBLOCK_UPDATE" = "true" ]; then
	dd if=Image/idblock.bin of=${RAWIMG} seek=${LOADER1_START} conv=notrunc
else
	dd if=Image/idbloader.img of=${RAWIMG} seek=${LOADER1_START} conv=notrunc
fi

for PARTITION in ${PARTITIONS[@]}; do
    PSTART=${PARTITION}_START_PARTITION
    PSTART=${!PSTART}

    IMGFILE=$(cat package-file | grep -wi ${PARTITION} | awk '{printf $2}' | sed 's/\r//g')

    if [[ x"$IMGFILE" != x ]]; then
		if [[ -f "$IMGFILE" ]]; then
			echo ${PARTITION} ${IMGFILE} ${PSTART}
			dd if=${IMGFILE}  of=${RAWIMG} seek=$(((${PSTART} + 0x00))) conv=notrunc,fsync
		else
			if [[ x"$IMGFILE" != xRESERVED ]]; then
				echo -e "\e[31m error: $IMGFILE not found! \e[0m"
			fi
		fi
    fi
done

if [ -e ${PARA_FILE}.orig ]
then
	mv ${PARA_FILE}.orig ${PARA_FILE}
	exit $?
else
	exit 0
fi

echo "mk raw img OK"
