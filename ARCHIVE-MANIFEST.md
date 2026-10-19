# FUR-602 固件归档清单（本地实测）

本清单的 SHA256 **全部由本地实际文件计算**，不是从工作流输出抄录。

## 25.12.2 已验证产物（run 38208789499 复用 run 38134666544）

| 资产 | 大小 (bytes) | 大小 (MiB) | 条目数 | zip SHA256 |
| --- | ---: | ---: | ---: | --- |
| `fur602-25.12.2-verified-firmware-from-38134666544-by-38208789499.zip` | 25095557 | 23.93 | 13 | `3f6b146da843950db12a9deda13b07bdb8a4b5857dc492cda9760349b72d30e8` |
| `fur602-25.12.2-verified-kmods-from-38134666544-by-38208789499.zip` | 47452528 | 45.25 | 1122 | `76a1e292be728090ea9153bb10c2c280e0bd8f160e2da0aed885a3f2ace56e78` |
| `fur602-25.12.2-verified-rescue-from-38134666544-by-38208789499.zip` | 11999189 | 11.44 | 2 | `f7a706e85db4ce58d9025aca78258798c8ec4c6e383ee63bc837a4fdc6a740ea` |

## 历史版本（GitHub 上已无 Artifacts，本地为唯一副本）

| 资产 | 版本 | 大小 (bytes) | 条目数 | zip SHA256 |
| --- | --- | ---: | ---: | --- |
| `honor-fur602-firmware.zip` | OpenWrt (early port) | 39343062 | 3 | `8afe59c8a1a4cb239f6899548691cfa43cee96e2e225882daf2b4eca6e98c608` |
| `honor-fur602-firmware-aa5e28a.zip` | ImmortalWrt 24.10 | 81646695 | 1096 | `0b3f379575fa03cc80cbb6988a18693a810c0bef7e0c946114ddef3b7c8f935d` |
| `fur602-25.12.2-firmware-38134666544-4fc16f2.zip` | ImmortalWrt 25.12.2 | 37043978 | 11 | `8150f4016fc47ae1b0d249911ba71ebf3ee2a526102ea18aaba44ab953408f09` |

## 可复制校验和清单（`sha256sum -c` 格式）

```
3f6b146da843950db12a9deda13b07bdb8a4b5857dc492cda9760349b72d30e8  fur602-25.12.2-verified-firmware-from-38134666544-by-38208789499.zip
76a1e292be728090ea9153bb10c2c280e0bd8f160e2da0aed885a3f2ace56e78  fur602-25.12.2-verified-kmods-from-38134666544-by-38208789499.zip
f7a706e85db4ce58d9025aca78258798c8ec4c6e383ee63bc837a4fdc6a740ea  fur602-25.12.2-verified-rescue-from-38134666544-by-38208789499.zip
8afe59c8a1a4cb239f6899548691cfa43cee96e2e225882daf2b4eca6e98c608  honor-fur602-firmware.zip
0b3f379575fa03cc80cbb6988a18693a810c0bef7e0c946114ddef3b7c8f935d  honor-fur602-firmware-aa5e28a.zip
8150f4016fc47ae1b0d249911ba71ebf3ee2a526102ea18aaba44ab953408f09  fur602-25.12.2-firmware-38134666544-4fc16f2.zip
```

## 建议的 Release 划分

### `fur602-immortalwrt-24.10-build-35108878566`

- `honor-fur602-firmware-aa5e28a.zip` — ImmortalWrt 24.10；来源：run 35108878566 (2026-09-16), artifacts already expired/absent

### `fur602-immortalwrt-25.12.2-build-38134666544`

- `fur602-25.12.2-verified-firmware-from-38134666544-by-38208789499.zip` — ImmortalWrt 25.12.2；来源：verify run 38208789499 -> build run 38134666544
- `fur602-25.12.2-verified-kmods-from-38134666544-by-38208789499.zip` — ImmortalWrt 25.12.2；来源：verify run 38208789499 -> build run 38134666544
- `fur602-25.12.2-verified-rescue-from-38134666544-by-38208789499.zip` — ImmortalWrt 25.12.2；来源：verify run 38208789499 -> build run 38134666544

### `fur602-immortalwrt-25.12.2-raw-38134666544`

- `fur602-25.12.2-firmware-38134666544-4fc16f2.zip` — ImmortalWrt 25.12.2；来源：raw firmware artifact of run 38134666544

### `fur602-openwrt-build-31935849413`

- `honor-fur602-firmware.zip` — OpenWrt (early port)；来源：run 31935849413 (2026-08-16), artifacts already expired/absent

