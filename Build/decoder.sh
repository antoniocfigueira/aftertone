#!/usr/bin/env bash
set -euo pipefail
root="$(pwd)"
version=8.1.3
prefix="$root/.build/decoder"
mkdir -p "$root/.build"
cd "$root/.build"
curl --retry 3 --fail --location "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz" -o ffmpeg.tar.xz
echo "7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3  ffmpeg.tar.xz" | shasum -a 256 -c -
tar xf ffmpeg.tar.xz
cd "ffmpeg-$version"
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
target="--target=arm64-apple-ios17.0"
./configure --prefix="$prefix" --target-os=darwin --arch=arm64 --enable-cross-compile \
  --cc="$(xcrun --sdk iphoneos -f clang)" --ar="$(xcrun --sdk iphoneos -f ar)" \
  --ranlib="$(xcrun --sdk iphoneos -f ranlib)" --sysroot="$sdk" \
  --extra-cflags="$target" --extra-ldflags="$target" \
  --disable-everything --disable-programs --disable-doc --disable-debug --disable-network --disable-autodetect \
  --disable-avdevice --disable-avfilter --disable-swscale --disable-videotoolbox --disable-audiotoolbox \
  --enable-protocol=file --enable-avcodec --enable-avformat --enable-swresample \
  --enable-demuxer='wav,aiff,caf,mp3,mov,aac,flac,ogg,matroska,asf,ape,wv,tta,ac3,eac3,dts,amr,au,dsf,dsdiff,mpc,mpc8,tak,ofr,spdif,w64' \
  --enable-parser='aac,aac_latm,mpegaudio,flac,opus,vorbis,ac3,dca' \
  --enable-decoder='pcm_*,adpcm_*,mp1*,mp2*,mp3*,aac,aac_latm,alac,flac,vorbis,opus,wmav1,wmav2,wmapro,wmalossless,ape,wavpack,tta,ac3,eac3,dca,amrnb,amrwb,dsd_*,mpc7,mpc8,tak,als,qdm2,mace3,mace6,shorten,speex'
make -j"$(sysctl -n hw.ncpu)"
make install

