#!/bin/bash

######################################
IMAGE_NAME="gcr.io/dancing-monkey/platform/kubernetes-kafka-with-prom-export"
IMAGE_VERSION="2.13-3.8.0"
######################################

if (($# == 2)); then
  PROJECT=$1
  CLUSTER_ENV=$2
  IMAGE_NAME="gcr.io/${PROJECT}/platform/${CLUSTER_ENV}/kubernetes-kafka-with-prom-export"
fi

scriptdir="$(dirname "$(which "$0")")"
cd $scriptdir

function removeUntaggedImages() {
    #remove untagged images
    echo ""
    untagged_images_count=`docker images | grep "<none>" | wc -l`
    if [ "$untagged_images_count" -gt "0" ]; then
        echo "Removing $untagged_images_count untagged image(s) .."
        docker rmi $(docker images | grep "<none>" | awk "{print $3}") 2>&1 > /dev/null
    fi
}

function removeStoppedContainers() {
    #remove stopped containers
    echo ""
    stopped_containers_count=$(docker ps -a -q | grep -v `docker ps -a -q --filter status=running` | wc -l)
    if [ "$stopped_containers_count" -gt "0" ]; then
        echo "Removing $stopped_containers_count stopped container(s) .."
        docker rm -f $(docker ps -a -q | grep -v `docker ps -a -q --filter status=running`) 2>&1 > /dev/null
    fi
    echo ""
}

removeUntaggedImages
removeStoppedContainers

IMAGE=$IMAGE_NAME":"$IMAGE_VERSION
echo ""
echo "Building docker image $IMAGE .."
echo ""
docker build -t $IMAGE .


status=$?
if [ "$status" -eq "0" ]; then
    echo "Image created successfully, pushing image to registry .."
    docker push $IMAGE
    status=$?
    if [ "$status" -eq "0" ]; then
        echo "Image pushed to registry successfully !!"
        removeUntaggedImages
        removeStoppedContainers
        echo "Done"
    else
        echo "Image push to the registry failed, exiting"
        exit 1
    fi
else
    echo "Image creating failed, exiting"
    exit 1
fi
