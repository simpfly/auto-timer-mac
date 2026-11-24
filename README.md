<div align="center">

<img src="assets/icon.png" width="120" height="120" alt="It's Time" />

# It's Time

**macOS 原生极简定时自动化助手**

菜单栏常驻 · 自然语言创建 · 锁屏/休眠智能跳过 · 屏幕时间统计

[![macOS](https://img.shields.io/badge/Platform-macOS%2013%2B-black?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Language-Swift%205.9-orange?style=flat-square&logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

</div>

---

## 功能概览

### 四种触发模式

| 模式 | 说明 | 示例 |
| :--- | :--- | :--- |
| **倒计时** | 从现在起计时，归零触发 | 25 分钟番茄钟 |
| **每日定时** | 每天固定时刻触发 | 每天 09:30 站会 |
| **循环间隔** | 按固定周期反复触发 | 每 45 分钟做眼保健操 |
| **单次定时** | 指定某个具体时刻，触发一次后停止 | 今天 15:00 开会 |

### 四种到期动作

| 动作 | 说明 |
| :--- | :--- |
| **文本提示** | 居中毛玻璃浮层大字展示，不抢焦点 |
| **声音通知** | 播放清脆系统提示音 + 系统通知 |
| **播放音频** | 淡入播放本地 MP3/WAV，播放时自动防休眠，播完自动释放 |
| **打开链接** | 自动唤起浏览器或会议客户端（腾讯会议、飞书、Zoom 等） |

弹窗还支持三种内容模式：纯文本提示 / 自定义待办清单 / 今日系统日历日程。

---

## 核心特性

**自然语言快速创建**
直接在输入框输入"半小时后提醒我出门"、"每45分钟"、"下午3点评审"，自动识别时间模式并填入，回车即启动。

**菜单栏常驻**
应用运行于状态栏，零 Dock 占用。点击图标呼出紧凑面板，显示进行中的倒计时与即将触发的任务；正在计时时菜单栏图标实时显示剩余时间。

**全天时间轴**
主窗口和菜单栏面板均内嵌非等比彩色时间带，一眼看清全天所有任务的时间分布与剩余时间。

**锁屏 / 休眠智能跳过**
锁屏、息屏、合盖时立即停止音频与弹窗，并刷新任务周期——唤醒解锁后不会补发错过的提醒，也不会立即误触发。

**音频 5 秒预告**
音频类任务触发前 5 秒弹出悬浮预告卡片，显示倒数秒数与音频名称，支持"立即播放"与"跳过本次"。

**系统日历联动**
通过 EventKit 对接系统日历与提醒事项，今日日程自动流转呈现在弹窗看板中，并可一键导入为定时任务。

**屏幕时间统计**
可选开启本地屏幕时间追踪：记录今日活跃时长（息屏/锁屏/闲置自动暂停）、前台应用使用分布、各定时任务历史触发次数，支持日 / 周 / 月 / 年视图切换，数据全部本地存储。

**开机自启动**
一键通过 `SMAppService` 注册为登录项，无需手动配置。

---

## 界面预览

### 主窗口

<div align="center">
  <img src="assets/main-window.png" width="85%" alt="主窗口" />
</div>

<br/>

### 菜单栏面板

<div align="center">
  <img src="assets/menubar-panel.png" width="60%" alt="菜单栏面板" />
</div>

---

## 安装与运行

### 构建独立应用

```bash
git clone https://github.com/simpfly/its-time-mac.git
cd its-time-mac
./build_app.sh
open "It's Time.app"
```

### 开发调试

```bash
swift build
swift test
```

---

## 技术说明

- **语言 / UI**：Swift 5.9 + SwiftUI + AppKit
- **调度内核**：1 秒精度 Combine Timer，锁屏/休眠/息屏全链路拦截
- **音频**：AVFoundation，淡入淡出 + IOKit 防休眠锁
- **日历**：EventKit（需用户授权）
- **自启动**：ServiceManagement `SMAppService`（macOS 13+）
- **数据存储**：UserDefaults，全本地，零网络请求
- **最低系统要求**：macOS 13 Ventura

---

## 开源协议

[MIT](LICENSE)
