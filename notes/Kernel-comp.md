# Kernel compiling

In the first step fetch the source code:

```bash
curl -sLO https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.19.4.tar.xz
```

Install the required tools to build the Linux kernel (example for `Ubuntu 18.04`):

```bash
sudo apt-get install git fakeroot build-essential ncurses-dev xz-utils libssl-dev bc flex libelf-dev bison
```

Now we can unpack the source code:

```bash
tar xfJ linux-4.19.4.tar.xz
```

And jump into the newly created directory `cd linux-4.19.4` and configure the Linux Kernel modules `cp /boot/config-$(uname -r) .config`. Now you can run `make`  after answering all these questions run `make modules_install`.
