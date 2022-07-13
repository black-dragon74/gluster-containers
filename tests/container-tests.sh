#!/bin/bash

# This test is supposed to run after the linter tests.
# Exit if any of the commands return a non zero exit code.
set -e

if [[ -z $1 ]]; then
  echo "Usage: $0 <fedora|centos>"
  exit 1
fi

# We need to have docker installed to run this test.
which docker > /dev/null 2>&1 || {
    echo "docker is not installed. Please install docker first."
    exit 1
}

BUILD_TAG="${1}-test"
BUILD_VARIANT="../CentOS"

if [[ $BUILD_TAG == "fedora-test" ]]; then
    BUILD_VARIANT="../Fedora"
fi

build_image() {
    echo "Building image for ${BUILD_TAG}"
    docker build -t $BUILD_TAG $BUILD_VARIANT
}

run_image() {
    echo "Trying to run the built image"
    # Make the required dirs
    sudo mkdir -p /home/gluster/etc/glusterfs \
        /home/gluster/var/log/glusterfs \
        /home/gluster/var/lib/glusterd


    # Run the container and sleep for a while to let it start
    docker run -d --rm --name=$BUILD_TAG \
        -v /home/gluster/etc/glusterfs:/etc/glusterfs:z \
        -v /home/gluster/var/log/glusterfs:/var/log/glusterfs:z \
        -v /home/gluster/var/lib/glusterd:/var/lib/glusterd:z \
        -v /dev:/dev:z \
        -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        --privileged --cgroupns=host --net=host \
        $BUILD_TAG

    echo "Container started. Sleeping for 15 seconds to let it boot."
    sleep 15
}

query_image() {
    echo "Checking glusterd status in the built image"

    # Check if the glusterd is running in the container
    docker exec -it $BUILD_TAG \
        systemctl is-active glusterd | grep -o "active" || \
        { echo "glusterd is not running in the container"; exit 1; }
}

clean_image() {
    echo "Test for container ${BUILD_TAG} failed! Cleaning up."

    # This may be called on some other error too. Check if the container is built or not.
    if [[ $(docker images -q $BUILD_TAG) ]]; then
        # Check if the container is running or not.
        if [[ $(docker ps -q -f name=$BUILD_TAG) ]]; then
            # Stop the container
            docker stop $BUILD_TAG

            # The image will be removed automatically when the container is stopped.
            # As it was started with '--rm' flag.
        fi

        # The container failed to start or was not started, we need to remove the image manually.
        docker rmi $BUILD_TAG
    fi

    # Remove the directories we created for the container.
    sudo rm -rf /home/gluster/etc/glusterfs \
        /home/gluster/var/log/glusterfs \
        /home/gluster/var/lib/glusterd
}

main() {
    echo "Running tests for container ${BUILD_TAG}, building from ${BUILD_VARIANT}"

    build_image
    run_image
    query_image
    clean_image
}

trap clean_image EXIT
main

echo "Successfully completed running tests for container ${BUILD_TAG}"
exit 0
