import Foundation

enum DotKind {
    /// Part of macOS or the shell itself.
    case system
    /// Keys, tokens, credentials: never suggest deleting.
    case secret
    /// Hand-written or tool configuration the user relies on.
    case config
    /// Command histories: deletable, only loses history.
    case history
    /// Regenerated automatically.
    case cache
    /// Data belonging to one tool; deletable once that tool is gone.
    case data
    /// Language runtimes and version managers, detailed in the dev-env section.
    case toolchain
    /// Container whose contents are itemized in the cache section; kept here so sizes aren't counted twice.
    case itemizedElsewhere
}

struct DotInfo {
    let what: String
    let owner: String
    let kind: DotKind
    var apps: [String] = []
    var commands: [String] = []
    var guess = false
    var suggestion: String? = nil
}

private let jetbrainsApps = ["jetbrains", "intellij", "goland", "pycharm", "webstorm", "clion", "datagrip", "phpstorm", "rider", "rubymine"]
private let vscodeApps = ["visual studio code", "com.microsoft.vscode", "cursor", "windsurf", "vscodium"]

let dotfileKB: [String: DotInfo] = [
    ".CFUserTextEncoding": DotInfo(what: "macOS 记录当前用户的文本编码设置", owner: "macOS", kind: .system),
    ".DS_Store": DotInfo(what: "访达保存的文件夹显示设置（图标位置、排序等）", owner: "访达", kind: .cache),
    ".cups": DotInfo(what: "打印系统 CUPS 的个人打印选项", owner: "macOS 打印", kind: .system),
    ".zsh_sessions": DotInfo(what: "「终端」App 为恢复窗口保存的每个会话的历史", owner: "终端", kind: .cache),

    ".ssh": DotInfo(what: "SSH 私钥、公钥和已知主机列表", owner: "SSH", kind: .secret),
    ".gnupg": DotInfo(what: "GPG 密钥环（加密、签名用的私钥）", owner: "GnuPG", kind: .secret),
    ".git-credentials": DotInfo(what: "Git 以【明文】保存的账号密码或令牌", owner: "Git", kind: .secret,
                                suggestion: "建议改用钥匙串：git config --global credential.helper osxkeychain，确认能推送后再删此文件"),
    ".npmrc": DotInfo(what: "npm 配置，可能包含私有仓库地址和登录令牌", owner: "npm", kind: .secret),
    ".netrc": DotInfo(what: "curl/ftp 等工具保存的明文登录信息", owner: "多个工具", kind: .secret),

    ".zshrc": DotInfo(what: "zsh 每次打开终端都会执行的配置", owner: "zsh", kind: .config),
    ".zprofile": DotInfo(what: "zsh 登录时执行的配置（Homebrew 路径常写在这里）", owner: "zsh", kind: .config),
    ".zshenv": DotInfo(what: "zsh 所有场景都会读取的环境变量配置", owner: "zsh", kind: .config),
    ".zsh_history": DotInfo(what: "zsh 命令历史（Ctrl+R 搜索、本报告的命令使用时间都依赖它）", owner: "zsh", kind: .config),
    ".bash_profile": DotInfo(what: "bash 登录时执行的配置", owner: "bash", kind: .config),
    ".bashrc": DotInfo(what: "bash 交互式配置", owner: "bash", kind: .config),
    ".profile": DotInfo(what: "通用 shell 登录配置（bash/sh 会读取）", owner: "shell", kind: .config),
    ".gitconfig": DotInfo(what: "Git 全局配置（用户名、邮箱、别名等）", owner: "Git", kind: .config),
    ".gitignore_global": DotInfo(what: "Git 全局忽略规则", owner: "Git", kind: .config),
    ".config": DotInfo(what: "多个命令行工具共用的配置目录（XDG 规范）", owner: "多个工具", kind: .config),
    ".local": DotInfo(what: "用户级程序和数据目录（XDG 规范，pipx、uv 等会装到这里）", owner: "多个工具", kind: .config),
    ".oh-my-zsh": DotInfo(what: "zsh 配置框架 oh-my-zsh（主题、插件）", owner: "oh-my-zsh", kind: .config),
    ".vim": DotInfo(what: "Vim 插件和配置", owner: "Vim", kind: .config),
    ".vimrc": DotInfo(what: "Vim 配置", owner: "Vim", kind: .config),
    ".yarnrc": DotInfo(what: "Yarn 配置", owner: "Yarn", kind: .config, commands: ["yarn"]),
    ".idlerc": DotInfo(what: "Python 自带编辑器 IDLE 的配置", owner: "Python IDLE", kind: .config),

    ".bash_history": DotInfo(what: "bash 的命令历史（你现在用的是 zsh）", owner: "bash", kind: .history),
    ".lesshst": DotInfo(what: "less 分页器的搜索历史", owner: "less", kind: .history),
    ".viminfo": DotInfo(what: "Vim 的编辑历史（打开过的文件、搜索记录）", owner: "Vim", kind: .history),
    ".python_history": DotInfo(what: "Python 交互模式的输入历史", owner: "Python", kind: .history),
    ".node_repl_history": DotInfo(what: "Node.js 交互模式的输入历史", owner: "Node.js", kind: .history),
    ".mysql_history": DotInfo(what: "mysql 命令行客户端的输入历史（可能含 SQL 里的敏感数据）", owner: "MySQL 客户端", kind: .history),
    ".wget-hsts": DotInfo(what: "wget 记录的强制 HTTPS 网站列表", owner: "wget", kind: .history),

    ".cache": DotInfo(what: "多个命令行工具共用的缓存目录（XDG 规范）", owner: "多个工具", kind: .itemizedElsewhere),
    ".npm": DotInfo(what: "npm 的下载缓存和日志", owner: "npm", kind: .itemizedElsewhere),
    ".matplotlib": DotInfo(what: "Python 绘图库 matplotlib 的字体缓存", owner: "matplotlib", kind: .cache),

    ".nvm": DotInfo(what: "Node.js 版本管理器 nvm 及其安装的 Node 版本（明细见「开发环境」）", owner: "nvm", kind: .toolchain),
    ".rbenv": DotInfo(what: "Ruby 版本管理器 rbenv 及其安装的 Ruby 版本（明细见「开发环境」）", owner: "rbenv", kind: .toolchain),
    ".pyenv": DotInfo(what: "Python 版本管理器 pyenv 及其安装的 Python 版本", owner: "pyenv", kind: .toolchain),
    ".cargo": DotInfo(what: "Rust 工具链 cargo 的程序和缓存", owner: "Rust", kind: .toolchain),
    ".rustup": DotInfo(what: "Rust 版本管理器 rustup 安装的工具链", owner: "Rust", kind: .toolchain),

    ".android": DotInfo(what: "Android 开发工具（adb、模拟器、Android Studio）的配置和调试密钥", owner: "Android SDK / Android Studio",
                        kind: .data, apps: ["android studio"], commands: ["adb", "emulator"]),
    ".anyconnect": DotInfo(what: "Cisco AnyConnect VPN 客户端的用户配置", owner: "Cisco AnyConnect", kind: .data,
                           apps: ["anyconnect", "cisco secure client"]),
    ".ShadowsocksX": DotInfo(what: "ShadowsocksX 代理客户端的配置和规则", owner: "ShadowsocksX", kind: .data, apps: ["shadowsocks"]),
    ".bundle": DotInfo(what: "Ruby Bundler 的全局配置和缓存", owner: "Bundler（Ruby）", kind: .data, commands: ["bundle"]),
    ".gem": DotInfo(what: "RubyGems 用户级安装的 gem 和缓存", owner: "RubyGems", kind: .data, commands: ["gem"]),
    ".bytertc": DotInfo(what: "字节跳动火山 RTC 音视频 SDK 的监控日志", owner: "字节系应用（飞书等）", kind: .data,
                        apps: ["lark", "feishu", "飞书", "bytedance", "抖音", "剪映", "capcut"], guess: true),
    ".codex": DotInfo(what: "OpenAI Codex 的配置、会话记录和技能（Cursor 等工具也会读取这里的 skills）", owner: "Codex / Cursor",
                      kind: .data, apps: ["codex", "cursor"], commands: ["codex"]),
    ".cursor": DotInfo(what: "Cursor 编辑器的扩展、设置和 AI 会话数据", owner: "Cursor", kind: .data, apps: ["cursor"]),
    ".vscode": DotInfo(what: "VS Code 的扩展和设置", owner: "VS Code", kind: .data, apps: vscodeApps),
    ".vscode-react-native": DotInfo(what: "VS Code 扩展 React Native Tools 的数据", owner: "VS Code", kind: .data, apps: vscodeApps),
    ".dlv": DotInfo(what: "Go 调试器 Delve 的配置", owner: "Delve", kind: .data, commands: ["dlv"]),
    ".docker": DotInfo(what: "Docker 命令行的配置、登录凭据和插件", owner: "Docker", kind: .data, apps: ["docker"], commands: ["docker"]),
    ".kratos": DotInfo(what: "Go 微服务框架 Kratos 命令行工具的模板仓库缓存", owner: "Kratos CLI", kind: .data, commands: ["kratos"]),
    ".lldb": DotInfo(what: "LLDB 调试器的配置和历史", owner: "LLDB", kind: .data, commands: ["lldb"]),
    ".swiftpm": DotInfo(what: "Swift Package Manager 的配置和缓存", owner: "Swift", kind: .data, commands: ["swift"]),
    ".tor": DotInfo(what: "Tor 匿名网络的数据", owner: "Tor", kind: .data, apps: ["tor browser"], commands: ["tor"]),
    ".jetbrains": DotInfo(what: "JetBrains IDE（IntelliJ、GoLand、PyCharm 等）的共享数据", owner: "JetBrains IDE", kind: .data, apps: jetbrainsApps),
    ".jetbrains.vmoptions.sh": DotInfo(what: "JetBrains IDE 的 JVM 启动参数脚本，通常由第三方激活工具（如 ja-netfilter）写入",
                                       owner: "JetBrains IDE", kind: .data, apps: jetbrainsApps, guess: true),
    ".gongfeng_copilot": DotInfo(what: "腾讯工蜂 Copilot（IDE 里的 AI 编程助手插件）的配置", owner: "腾讯工蜂 Copilot", kind: .data),
    ".wns": DotInfo(what: "腾讯 WNS 网络 SDK 的数据，里面是 QQ 音乐（com.tencent.QQMusicMac）的目录", owner: "QQ 音乐", kind: .data,
                    apps: ["qqmusic", "qq音乐"]),
    ".grokbot": DotInfo(what: "Grok 本地执行守护进程的设置、凭据和日志", owner: "Grok", kind: .data, apps: ["grok"], commands: ["grok", "grokbot"], guess: true),
    ".jvs": DotInfo(what: "里面是 .openclaw，像是 OpenClaw（AI 智能体）的数据", owner: "OpenClaw", kind: .data, apps: ["openclaw"],
                    commands: ["openclaw"], guess: true),
]

func lookupDotfile(_ name: String) -> DotInfo? {
    if let info = dotfileKB[name] { return info }
    if name.hasPrefix(".zcompdump") {
        return DotInfo(what: "zsh 补全缓存，删除后下次打开终端会自动重建", owner: "zsh", kind: .cache)
    }
    if name.hasPrefix(".v8flags") {
        return DotInfo(what: "gulp 等 Node 工具缓存的 V8 参数列表", owner: "Node 工具", kind: .cache)
    }
    if name.hasSuffix("_history") || name.hasSuffix("hst") {
        return DotInfo(what: "某个命令行工具的输入历史", owner: "未知", kind: .history)
    }
    return nil
}

/// ~/Library folder names that don't match their app's name.
struct LibAlias {
    let owner: String
    var apps: [String] = []
    var commands: [String] = []
}

let libraryAliases: [String: LibAlias] = {
    var m = [String: LibAlias]()
    func add(_ names: [String], _ alias: LibAlias) { names.forEach { m[$0.lowercased()] = alias } }
    add(["PremiumSoft CyberTech"], LibAlias(owner: "Navicat", apps: ["navicat"]))
    add(["wpsmeeting", "WPKCaches", "wpkdata"], LibAlias(owner: "WPS Office", apps: ["wps"]))
    add(["Matrix"], LibAlias(owner: "微信（腾讯 Matrix 性能监控 SDK）", apps: ["wechat", "com.tencent.xinwechat"]))
    add(["lv", "ve"], LibAlias(owner: "剪映 / CapCut", apps: ["capcut", "剪映", "videofusion"]))
    add(["YachData", "知音楼"], LibAlias(owner: "知音楼", apps: ["知音楼", "yach"]))
    add(["Zhumu", "ZhumuChat"], LibAlias(owner: "瞩目", apps: ["zhumu", "瞩目"]))
    add(["UmeetingChat"], LibAlias(owner: "Umeeting", apps: ["umeeting"]))
    add(["ZoomSDKChat", "ZoomPhone"], LibAlias(owner: "Zoom 或基于 Zoom 的会议软件", apps: ["zoom", "zhumu", "umeeting"]))
    add(["WeComAgent", "WeComWeAgent"], LibAlias(owner: "企业微信", apps: ["企业微信", "wework", "wecom"]))
    add(["com.tencent"], LibAlias(owner: "腾讯系应用", apps: ["com.tencent"]))
    add(["DingTalk", "DingTalkMac", "dinglive"], LibAlias(owner: "钉钉", apps: ["dingtalk", "钉钉"]))
    add(["BaiduMacHi"], LibAlias(owner: "百度输入法", apps: ["baidu"]))
    add(["baidunetdisk", "BaiduNetdisk_mac"], LibAlias(owner: "百度网盘", apps: ["baidunetdisk", "百度网盘"]))
    add(["Fortinet", "FortiClient"], LibAlias(owner: "FortiClient VPN", apps: ["forticlient"]))
    add(["AweSun"], LibAlias(owner: "向日葵远程控制", apps: ["awesun", "向日葵", "sunlogin"]))
    add(["aDrive"], LibAlias(owner: "阿里云盘", apps: ["adrive", "阿里云盘"]))
    add(["GitKrakenCLI", "gk"], LibAlias(owner: "GitKraken", apps: ["gitkraken"], commands: ["gk"]))
    add(["Fellou", "fellou-updater"], LibAlias(owner: "Fellou 浏览器", apps: ["fellou"]))
    add(["Claude"], LibAlias(owner: "Claude", apps: ["claude"], commands: ["claude"]))
    add(["Codex"], LibAlias(owner: "Codex", apps: ["codex"], commands: ["codex"]))
    add(["OpenAI"], LibAlias(owner: "ChatGPT", apps: ["chatgpt", "openai"]))
    add(["Quark"], LibAlias(owner: "夸克", apps: ["quark", "夸克"]))
    add(["Thunder"], LibAlias(owner: "迅雷", apps: ["thunder", "迅雷"]))
    add(["Sogou", "SogouServices.binarycookies", "SogouUninstallHelper"], LibAlias(owner: "搜狗输入法", apps: ["sogou", "搜狗"]))
    add(["ToDesk"], LibAlias(owner: "ToDesk", apps: ["todesk"]))
    add(["OKX", "okx-uuid.json"], LibAlias(owner: "OKX", apps: ["okx"]))
    add(["微信开发者工具"], LibAlias(owner: "微信开发者工具", apps: ["wechatwebdevtools", "微信开发者工具"]))
    add(["Microsoft Remote Desktop Beta"], LibAlias(owner: "微软远程桌面", apps: ["remote desktop", "windows app"]))
    add(["Microsoft"], LibAlias(owner: "微软系应用", apps: ["microsoft"]))
    add(["DuckDuckGo", "DuckAiNativeStorage"], LibAlias(owner: "DuckDuckGo 浏览器", apps: ["duckduckgo"]))
    add(["ksfetch"], LibAlias(owner: "Google 自动更新（Chrome）", apps: ["com.google.chrome"]))
    add(["rules"], LibAlias(owner: "广告过滤规则（某个浏览器或代理工具）"))
    add(["go"], LibAlias(owner: "Go 工具链（遥测数据、构建缓存）", commands: ["go"]))
    add(["agora-iris.log"], LibAlias(owner: "声网 Agora 音视频 SDK（某个会议/直播应用）"))
    add(["KSCrash", "SentryCrash", "io.sentry", "statsig-cache", "apolloCache", "light_cache", "JetPackCache",
         "chrome_crashpad_handler", "CEF", "Chromium", "flutter_engine", "MiniLauncher", "jdyJitterMonitor", "INSTALLATION"],
        LibAlias(owner: "某个应用内置的 SDK（崩溃上报、统计、浏览器内核等）"))
    return m
}()

/// Developer-tool caches that live in ~/Library/Caches under the tool's name.
let toolCaches: [String: String] = [
    "go-build": "Go 编译缓存（go clean -cache）",
    "goimports": "Go 编辑器插件 goimports 的索引缓存",
    "gopls": "Go 语言服务器 gopls 的索引缓存",
    "ms-playwright": "Playwright 下载的测试浏览器（用 Playwright 时会重新下载）",
    "node-gyp": "node-gyp 编译原生模块用的 Node 头文件",
    "typescript": "TypeScript 编辑器的类型声明缓存",
    "prisma-nodejs": "Prisma 的引擎缓存",
    "checkpoint-nodejs": "Prisma 的版本检查缓存",
    "js-v8flags": "gulp 等 Node 工具缓存的 V8 参数",
    "JNA": "Java JNA 本地库缓存",
    "fanal": "Trivy 镜像扫描器的缓存",
    "pip": "pip 下载缓存",
    "Yarn": "Yarn 缓存",
    "pnpm": "pnpm 缓存",
    "CocoaPods": "CocoaPods 缓存",
    "Homebrew": "Homebrew 下载缓存",
    "deno": "Deno 缓存",
    "bun": "Bun 缓存",
]

/// Folders in ~/Library that belong to macOS itself even though they are not named com.apple.*.
let appleLibraryNames: Set<String> = [
    "accountsd", "appplaceholdersyncd", "stickersd", "syncdefaultsd", "askpermissiond", "sharedfilelistd", "diagnostics_agent",
    "knowledge-agent", "MobileMeAccounts", "Quick Look", "System Preferences", "AppAnalytics", "Baseband", "CoreSimulator",
    "DiscRecording.log", "PrivacyPreservingMeasurement", "SMSMigrator", "fsck_hfs.log", "walletAvailabilityCheckTool",
    "Databases", "WebPush", "default.store", "default.store-shm", "default.store-wal", "dmd", "libCachedImageData",
    "mbuseragent", "ssu", "UpdateJob", "Final Cut Pro", "Motion", "Compressor", "ProApps", "Xcode",
    "AddressBook", "CallHistoryDB", "CallHistoryTransactions", "CloudDocs", "CrashReporter", "DiskImages", "FileProvider",
    "Knowledge", "MobileSync", "SyncServices", "iCloud", "icdd", "networkserviceproxy", "Dock", "Animoji", "AppleMediaServices",
    "AppStoreComponents", "ContextStoreAgent", "DifferentialPrivacy", "FaceTime", "Accounts", "AppleIntelligence", "Mail",
    "Safari", "Siri", "Spotlight", "Photos", "Maps", "Messages", "Notes", "Reminders", "Calendars", "Weather", "Stocks",
    "SharedImageCache", "GeoServices", "PassKit", "Wallet", "PhotoAnalysis", "Group Containers", "familycircled", "homed",
    "identityservicesd", "locationaccessstored", "tipsd", "transparencyd", "videosubscriptionsd", "ScreenTimeAgent",
    "CoreParsec", "SiriTTS", "TrustedPeersHelper", "CloudKit", "Containers", "Metadata", "FontRegistry", "Caches",
    "MediaAnalysis", "Ubiquity", "assetsd", "bird", "com.crashlytics", "Preferences", "SESStorage", "GameKit",
    "PersonalizationPortrait", "AssetCache", "audiomxd", "akd", "Biome", "DuetExpertCenter", "Logs", "DiagnosticReports",
    "CoreSpeech", "Address Book Plug-Ins", "Fonts", "Sounds", "LanguageModeling", "ColorSync", "Keychains", "Autosave Information",
    "Cookies", "HTTPStorages", "WebKit", "Saved Application State", "AppleIntelligencePlatform", "ModelCatalog", "Trial",
    "Logic", "GarageBand", "iLifeMediaBrowser", "Script Editor", "ByHost", "SystemConfiguration", "BTServer", "Audio",
    "OpenDirectory", "DiscRecording", "Logging", "App Store", "ControlCenter", "FamilyCircle", "SiriTTSService", "Xsan",
    "PhotosSearch.aapbz", "PhotosUpgrade.aapbz", "Desktop Pictures", "Assistant", "is.workflow.my.app", "icloudmailagent",
    "TVRemoteAudio.driver", "iMovie", "Keynote", "Pages", "Numbers", "MobileDevice", "AirPlay", "Bluetooth",
    // Third-party drivers that macOS itself installs into /Library/Extensions.
    "SoftRAID.kext", "HighPointRR.kext", "HighPointIOP.kext", "ATTOCelerityFC8.kext", "ATTOExpressSASHBA2.kext",
    "ATTOExpressSASRAID2.kext", "ArcMSR.kext", "CalDigitHDSD.kext", "PromiseSTEX.kext", "ACS6x.kext", "ATTOExpressSASHBA3.kext",
]

/// Library entries whose name starts with one of these belong to the given owner.
let libraryPrefixAliases: [(prefix: String, alias: LibAlias)] = [
    ("org.cups.", LibAlias(owner: "macOS 打印系统")),
    ("jetbrains.iu.", LibAlias(owner: "IntelliJ IDEA", apps: ["com.jetbrains.intellij"])),
    ("jetbrains.jetprofile", LibAlias(owner: "JetBrains IDE", apps: ["jetbrains", "intellij"])),
    ("com.jetbrains.cefserver", LibAlias(owner: "JetBrains IDE", apps: ["jetbrains", "intellij"])),
    ("org.jcef.jcef", LibAlias(owner: "JetBrains IDE", apps: ["jetbrains", "intellij"])),
    ("jetbrains.vmoptions", LibAlias(owner: "JetBrains IDE（第三方激活工具）", apps: ["jetbrains", "intellij"])),
    ("jetbrains.db.", LibAlias(owner: "DataGrip", apps: ["datagrip"])),
    ("com.jetbrains.datagrip", LibAlias(owner: "DataGrip", apps: ["datagrip"])),
    ("com.jetbrains.goland", LibAlias(owner: "GoLand", apps: ["goland"])),
    ("com.electron.dockerdesktop", LibAlias(owner: "Docker", apps: ["com.docker.docker"])),
    ("com.ebus.lark", LibAlias(owner: "飞书", apps: ["com.electron.lark"])),
    ("com.prect.navicat", LibAlias(owner: "Navicat", apps: ["navicat"])),
    ("codex-runtimes", LibAlias(owner: "Codex", apps: ["codex", "cursor"], commands: ["codex"])),
    ("github-copilot", LibAlias(owner: "GitHub Copilot（编辑器插件）", apps: ["cursor", "visual studio code", "intellij"])),
    ("com.tencent.rqd", LibAlias(owner: "腾讯系应用内置的崩溃上报 SDK")),
    ("com.tencent.bugly", LibAlias(owner: "腾讯系应用内置的崩溃上报 SDK")),
    ("com.tencent.tds.bugly", LibAlias(owner: "腾讯系应用内置的崩溃上报 SDK")),
    ("com.tencent.fireeye", LibAlias(owner: "腾讯系应用内置的崩溃上报 SDK")),
]

func libraryAlias(for id: String) -> LibAlias? {
    let lower = id.lowercased()
    return libraryAliases[lower] ?? libraryPrefixAliases.first { lower.hasPrefix($0.prefix) }?.alias
}
