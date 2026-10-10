# F50 / Android 13 su 兼容说明

这个 fork 基于 [dikeckaan/mu300-linux](https://github.com/dikeckaan/mu300-linux)，加入 F50 / MU300 在 Android 13 下的 Root 路径兼容和 Windows PowerShell 哈希兼容修复。已验证的设备固件为 `F50_FLYMODEM_ZYV1.0.0B13`，Root 位于 `/debug_ramdisk/su`。

## 安装与卸载

设备应启动到已 Root 的 Android，开启 USB 调试，并授权电脑及 Root 请求。Windows 使用兼容入口：

```powershell
.\install-su-fallback.cmd -Check -Lang zh
.\install-su-fallback.cmd -Lang zh
.\uninstall-su-fallback.cmd
```

macOS/Linux 使用：

```sh
sh install-su-fallback.sh --check
sh install-su-fallback.sh
sh uninstall-su-fallback.sh
```

后文沿用上游安装说明；在本分支安装或卸载时，请使用上述带 `su-fallback` 的入口。

这些入口关闭安装器的源码自更新，保留发布镜像下载和 SHA-256 校验。发布镜像仍从上游 `dikeckaan/mu300-linux` 下载，本 fork 不提供重新编译的镜像。Windows 可用 `-Release <tag>` 固定发布版本，shell 可用 `MU300_RELEASE=<tag>`。更新本分支源码可在干净的 Git 工作区运行 `git pull --ff-only`，或重新下载本 fork；合入上游时需要同时检查兼容入口是否需要更新。

## 修复内容

- 等待 `sys.boot_completed=1` 后，依次探测 `su`、`/debug_ramdisk/su`、`/sbin/su`、`/system/xbin/su`、`/system/bin/su`。只有命令成功且 `id -u` 返回 `0` 才使用该路径，并重试尚未就绪的 Root。
- 安装、卸载和维护工具共用 `tools/su-fallback.ps1` / `.sh`，通过 `MU300_SU` 向 vendor/GPU 提取子进程传递路径，解决提取时报 `su: inaccessible or not found` 的问题。
- Windows 兼容安装器通过 .NET 流式计算 SHA-256，解决缺少 `Get-FileHash` 的环境无法安装的问题。
- 二进制数据继续在设备端写入临时文件后由 `adb pull` 获取，避免部分 su 的终端处理改写换行。

相应测试及运行方法见 [测试说明](../tests/README.md)。

## 维护工具

在已 Root 的 Android 中，使用相应兼容工具：

| 工具 | 用途 |
|---|---|
| `tools/backup-device-su-fallback.sh` | 备份设备专有数据和启动链 |
| `tools/backup-full-su-fallback.sh` | 分块备份设备分区 |
| `tools/collect-logs-su-fallback.sh` | 回退 Android 后收集启动日志 |
| `tools/reset-password-su-fallback.sh` | 重置已安装 Linux 的密码 |
| `tools/android-import-hotspot-su-fallback.sh` | 导入 Android 热点配置 |
| `tools/install-magisk-module-su-fallback.sh` | 安装或移除 Android → Linux 切换模块 |

各工具的参数见对应脚本开头。备份和日志保存在执行工具的电脑上，含设备专有数据的文件应自行保管。

## Root 与 Linux 启动条件

su 路径修复解决的是 Android 内的提权问题。设备还必须具备启动修改过的 Linux boot 镜像的条件。

已验证的 B13 设备曾成功写入 `boot_b`，但引导日志出现 `partion boot, verify_ret:0x3 is invalid`，随后回退 Android。原因是该设备的 SPL 随槽位选择 TEE：`trustos_a` 已有验签绕过补丁，`trustos_b` 仍使用原版验证逻辑。因此 Android 有 Root，不能证明另一个槽位也能启动 Linux。

该设备在备份并核对启动链后修复了 b 槽 TEE，保留 B13 成功启动 OpenWrt，无需降级 B09。这是单台设备的验证结果，不代表其他设备可直接复制 TEE 分区。本分支安装器不包含自动解锁 BL 或刷写 TEE 的逻辑。

## 验证范围

2026-10-10 已在上述设备确认 OpenWrt 启动、USB 网络、SSH 服务及 LuCI 登录。默认 USB 地址为 `192.168.77.1`，SSH 使用安装时设置的密码。5G、Wi-Fi、后续重启和 Android/Linux 往返切换尚未逐项实测。

本仓库仅包含适配源码、说明和测试；设备分区备份、NV/校准数据、下载固件和安装产物不随适配发布。
