#!/bin/bash
source scripts/run-helper.sh
run-benchmark() {
    KML=$1
    KERNEL=$2
    TYPE=$3
    LOG=benchmark-logs/$(echo $KERNEL | cut -d/ -f3).log
    rm -f $LOG
    # we do not need to use regular path for nokml because they run on an
    # unpatch kernel already.
    if [[ $TYPE == "redis" ]]; then
        if [[ $KML == "kml" ]]; then
            BIN=/trusted/redis-server
        else
            BIN=/usr/local/bin/redis-server
        fi
    elif [[ $TYPE == "nginx" ]]; then
        if [[ $KML == "kml" ]]; then
            BIN=/trusted/nginx
        else
            BIN=/usr/sbin/nginx
        fi
    fi
    yes | ./scripts/image2rootfs.sh $TYPE alpine ext2
    for i in `seq 30`; do
        cp $TYPE.ext2 $TYPE.ext2.disposible
        delete_tap $TAP
        create_current_tap
        sleep 3
        taskset -c 1 firectl --firecracker-binary=$(pwd)/firecracker \
            --kernel $KERNEL \
            --tap-device=tap100/AA:FC:00:00:00:01 \
            --root-drive=$TYPE.ext2.disposible \
            --kernel-opts="panic=-1 pci=off reboot=k tsc=reliable ipv6.disable=1 init=/guest_start.sh $BIN" &

        vm=$!
        sleep 5
        if [[ $TYPE == "redis" ]]; then
            taskset -c 2 redis-benchmark --csv -h 192.168.100.2 -t get,set >> $LOG
        elif [[ $TYPE == "nginx" ]]; then
            taskset -c 2 ab -n 100000 -c 100 192.168.100.2/index.html >> $LOG
        fi
        pkill -9 firecracker
    done
}

# run-benchmark kml ./kernelbuild/lupine-djw-kml++nginx/vmlinux nginx
# run-benchmark kml ./kernelbuild/lupine-djw-kml-tiny++nginx/vmlinux nginx
# run-benchmark nokml ./kernelbuild/lupine-djw-nokml++nginx/vmlinux nginx
# run-benchmark nokml ./kernelbuild/lupine-djw-nokml-tiny++nginx/vmlinux nginx

# run-benchmark kml ./kernelbuild/lupine-djw-kml++redis/vmlinux redis
# run-benchmark kml ./kernelbuild/lupine-djw-kml-tiny++redis/vmlinux redis
# run-benchmark nokml ./kernelbuild/lupine-djw-nokml++redis/vmlinux redis
# run-benchmark nokml ./kernelbuild/lupine-djw-nokml-tiny++redis/vmlinux redis

for f in benchmark-logs/*.log; do
    if [[ $f == *"redis"* ]]; then
        printf "Redis $(basename $f | sed 's/djw-//' | sed 's/++redis//' | sed 's/.log//') "
        grep GET $f | cut -d',' -f2 | tr -d '"' | st | tail -n1
    fi
    if [[ $f == *"nginx"* ]]; then
        printf "Nginx $(basename $f | sed 's/djw-//' | sed 's/++nginx//' | sed 's/.log//') "
        grep Request $f | awk '{print $4}' | st | tail -n1
    fi
done
