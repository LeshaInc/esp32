{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    pkgs = import nixpkgs {system = "x86_64-linux";};
    esp32 = pkgs.dockerTools.pullImage {
      imageName = "espressif/idf-rust";
      imageDigest = "sha256:751323a0feecd48201a3cfe74ef34f40eeb8cdd6c5b07034a6804ce6a859ba3b";
      sha256 = "0jnkjczq9h6fmk7mmp10d3qd8902lzjn4l4sqlxnva6liiwkcm8c";
      finalImageName = "espressif/idf-rust";
      finalImageTag = "all_latest";
    };
    extractDocker = image:
      pkgs.vmTools.runInLinuxVM (
        pkgs.runCommand "docker-preload-image" {
          memSize = 36 * 1024;
          buildInputs = [
            pkgs.curl
            pkgs.kmod
            pkgs.docker
            pkgs.e2fsprogs
            pkgs.utillinux
          ];
        }
        ''
          modprobe overlay

          # from https://github.com/tianon/cgroupfs-mount/blob/master/cgroupfs-mount
          mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup
          cd /sys/fs/cgroup
          for sys in $(awk '!/^#/ { if ($4 == 1) print $1 }' /proc/cgroups); do
            mkdir -p $sys
            if ! mountpoint -q $sys; then
              if ! mount -n -t cgroup -o $sys cgroup $sys; then
                rmdir $sys || true
              fi
            fi
          done

          dockerd -H tcp://127.0.0.1:5555 -H unix:///var/run/docker.sock &

          until $(curl --output /dev/null --silent --connect-timeout 2 http://127.0.0.1:5555); do
            printf '.'
            sleep 1
          done

          echo load image
          docker load -i ${image}

          echo run image
          docker run ${image.destNameTag} tar -C /home/esp -c . | tar -xv --no-same-owner -C $out || true

          echo end
          kill %1
        ''
      );
  in {
    packages.x86_64-linux.esp32 = pkgs.stdenv.mkDerivation {
      name = "esp32";
      src = extractDocker esp32;
      nativeBuildInputs = [
        pkgs.autoPatchelfHook
      ];
      buildInputs = [
        pkgs.xz
        pkgs.zlib
        pkgs.libxml2
        pkgs.python2
        pkgs.libudev-zero
        pkgs.stdenv.cc.cc
      ];
      buildPhase = "true";
      installPhase = ''
        mkdir -p $out
        cp -r $src/.cargo $out
        cp -r $src/.rustup $out
      '';
    };
  };
}
