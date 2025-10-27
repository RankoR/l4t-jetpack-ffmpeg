set -ex

docker build --build-arg JETPACK_TAG=r36.4.0 --target main -t rankor777/l4t-jetpack-ffmpeg:36.4.0-ffmpeg-8.0 .