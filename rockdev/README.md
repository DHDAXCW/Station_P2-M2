## 生成固件的方式有两种：
### 第一种：rockchip固件
功能：支持线刷，SD卡升级(将SD卡固件刷到EMMC)，SD卡启动

做卡工具：Windows的**瑞芯微创建升级磁盘工具**

固件生成步骤：

```
将文件系统拷贝到Image目录，重命名为rootfs.img
$ cp rootfs.img Image

运行mkupdate.sh
$./mkupdate.sh

生成的固件放在Image中，文件名为update.img
```



### 第二种：raw固件

功能：仅支持SD卡启动

做卡工具：**balenaEtcher**

固件生成步骤：

```
将文件系统拷贝到Image目录，重命名为rootfs.img
$ cp rootfs.img Image

运行mkrawimg.sh
$./mkrawimg.sh

生成的固件放在Image中，文件名为raw.img
```



