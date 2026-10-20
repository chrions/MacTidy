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
    /// Container whose contents are itemized one by one.
    case itemizedElsewhere
}

/// `owner` doubles as a lookup key for toolchains and the shell shelf, so tool names stay untranslated.
struct DotInfo {
    let what: String
    let owner: String
    let kind: DotKind
    var apps: [String] = []
    var commands: [String] = []
    var guess = false
}

private let jetbrainsApps = ["jetbrains", "intellij", "goland", "pycharm", "webstorm", "clion", "datagrip", "phpstorm", "rider", "rubymine"]
private let vscodeApps = ["visual studio code", "com.microsoft.vscode", "cursor", "windsurf", "vscodium"]

let dotfileKB: [String: DotInfo] = [
    ".CFUserTextEncoding": DotInfo(what: L("Where macOS records your text encoding setting"), owner: "macOS", kind: .system),
    ".DS_Store": DotInfo(what: L("Finder's view settings for a folder (icon positions, sorting)"), owner: "Finder", kind: .cache),
    ".cups": DotInfo(what: L("Your personal options for the CUPS printing system"), owner: "macOS", kind: .system),
    ".zsh_sessions": DotInfo(what: L("History saved per session by Terminal to restore its windows"), owner: "Terminal", kind: .cache),

    ".ssh": DotInfo(what: L("SSH private and public keys, and the list of known hosts"), owner: "SSH", kind: .secret),
    ".gnupg": DotInfo(what: L("GPG keyring (private keys for encrypting and signing)"), owner: "GnuPG", kind: .secret),
    ".git-credentials": DotInfo(what: L("Git accounts, passwords or tokens stored in PLAIN TEXT"), owner: "Git", kind: .secret),
    ".npmrc": DotInfo(what: L("npm settings; may hold private registry addresses and login tokens"), owner: "npm", kind: .secret),
    ".netrc": DotInfo(what: L("Plain-text logins saved by curl, ftp and similar tools"), owner: L("Several tools"), kind: .secret),

    ".zshrc": DotInfo(what: L("zsh settings run every time a terminal opens"), owner: "zsh", kind: .config),
    ".zprofile": DotInfo(what: L("zsh settings run at login (Homebrew's PATH usually goes here)"), owner: "zsh", kind: .config),
    ".zshenv": DotInfo(what: L("Environment variables zsh reads in every situation"), owner: "zsh", kind: .config),
    ".zsh_history": DotInfo(what: L("zsh command history (Ctrl-R search and MacTidy's command usage both rely on it)"), owner: "zsh", kind: .config),
    ".bash_profile": DotInfo(what: L("bash settings run at login"), owner: "bash", kind: .config),
    ".bashrc": DotInfo(what: L("bash settings for interactive shells"), owner: "bash", kind: .config),
    ".profile": DotInfo(what: L("Generic shell login settings (read by bash and sh)"), owner: "shell", kind: .config),
    ".gitconfig": DotInfo(what: L("Git's global settings (name, email, aliases)"), owner: "Git", kind: .config),
    ".gitignore_global": DotInfo(what: L("Git's global ignore rules"), owner: "Git", kind: .config),
    ".config": DotInfo(what: L("Settings folder shared by many command-line tools (XDG)"), owner: L("Several tools"), kind: .config),
    ".local": DotInfo(what: L("Per-user programs and data (XDG; pipx, uv and others install here)"), owner: L("Several tools"), kind: .config),
    ".oh-my-zsh": DotInfo(what: L("The oh-my-zsh framework (themes and plug-ins for zsh)"), owner: "oh-my-zsh", kind: .config),
    ".vim": DotInfo(what: L("Vim plug-ins and settings"), owner: "Vim", kind: .config),
    ".vimrc": DotInfo(what: L("Vim settings"), owner: "Vim", kind: .config),
    ".yarnrc": DotInfo(what: L("Yarn settings"), owner: "Yarn", kind: .config, commands: ["yarn"]),
    ".idlerc": DotInfo(what: L("Settings for IDLE, the editor that comes with Python"), owner: "Python IDLE", kind: .config),

    ".bash_history": DotInfo(what: L("bash command history"), owner: "bash", kind: .history),
    ".lesshst": DotInfo(what: L("Search history of the less pager"), owner: "less", kind: .history),
    ".viminfo": DotInfo(what: L("Vim's editing history (files opened, searches)"), owner: "Vim", kind: .history),
    ".python_history": DotInfo(what: L("What you typed in interactive Python"), owner: "Python", kind: .history),
    ".node_repl_history": DotInfo(what: L("What you typed in the Node.js REPL"), owner: "Node.js", kind: .history),
    ".mysql_history": DotInfo(what: L("What you typed in the mysql client (may include sensitive data from SQL)"), owner: "MySQL", kind: .history),
    ".wget-hsts": DotInfo(what: L("Sites wget remembers as HTTPS-only"), owner: "wget", kind: .history),

    ".cache": DotInfo(what: L("Cache folder shared by many command-line tools (XDG)"), owner: L("Several tools"), kind: .itemizedElsewhere),
    ".npm": DotInfo(what: L("npm's download cache and logs"), owner: "npm", kind: .itemizedElsewhere),
    ".matplotlib": DotInfo(what: L("Font cache of the matplotlib plotting library"), owner: "matplotlib", kind: .cache),

    ".nvm": DotInfo(what: L("The nvm version manager and the Node versions it installed"), owner: "nvm", kind: .toolchain),
    ".rbenv": DotInfo(what: L("The rbenv version manager and the Ruby versions it installed"), owner: "rbenv", kind: .toolchain),
    ".pyenv": DotInfo(what: L("The pyenv version manager and the Python versions it installed"), owner: "pyenv", kind: .toolchain),
    ".cargo": DotInfo(what: L("Programs and caches of cargo, the Rust toolchain"), owner: "Rust", kind: .toolchain),
    ".rustup": DotInfo(what: L("Toolchains installed by rustup, the Rust version manager"), owner: "Rust", kind: .toolchain),

    ".android": DotInfo(what: L("Settings and debug keys of the Android tools (adb, emulator, Android Studio)"), owner: "Android SDK / Android Studio",
                        kind: .data, apps: ["android studio"], commands: ["adb", "emulator"]),
    ".anyconnect": DotInfo(what: L("User settings of the Cisco AnyConnect VPN client"), owner: "Cisco AnyConnect", kind: .data,
                           apps: ["anyconnect", "cisco secure client"]),
    ".ShadowsocksX": DotInfo(what: L("Settings and rules of the ShadowsocksX proxy client"), owner: "ShadowsocksX", kind: .data, apps: ["shadowsocks"]),
    ".bundle": DotInfo(what: L("Global settings and cache of Ruby's Bundler"), owner: "Bundler (Ruby)", kind: .data, commands: ["bundle"]),
    ".gem": DotInfo(what: L("Gems installed per user by RubyGems, and their cache"), owner: "RubyGems", kind: .data, commands: ["gem"]),
    ".bytertc": DotInfo(what: L("Monitoring logs of ByteDance's Volcano RTC audio/video SDK"), owner: L("ByteDance apps (Lark and others)"), kind: .data,
                        apps: ["lark", "feishu", "飞书", "bytedance", "抖音", "剪映", "capcut"], guess: true),
    ".codex": DotInfo(what: L("OpenAI Codex settings, sessions and skills (Cursor and other tools read the skills too)"), owner: "Codex / Cursor",
                      kind: .data, apps: ["codex", "cursor"], commands: ["codex"]),
    ".cursor": DotInfo(what: L("Extensions, settings and AI session data of the Cursor editor"), owner: "Cursor", kind: .data, apps: ["cursor"]),
    ".vscode": DotInfo(what: L("VS Code extensions and settings"), owner: "VS Code", kind: .data, apps: vscodeApps),
    ".vscode-react-native": DotInfo(what: L("Data of the React Native Tools extension for VS Code"), owner: "VS Code", kind: .data, apps: vscodeApps),
    ".dlv": DotInfo(what: L("Settings of Delve, the Go debugger"), owner: "Delve", kind: .data, commands: ["dlv"]),
    ".docker": DotInfo(what: L("Docker CLI settings, logins and plug-ins"), owner: "Docker", kind: .data, apps: ["docker"], commands: ["docker"]),
    ".kratos": DotInfo(what: L("Template cache of the Kratos CLI (a Go microservice framework)"), owner: "Kratos CLI", kind: .data, commands: ["kratos"]),
    ".lldb": DotInfo(what: L("Settings and history of the LLDB debugger"), owner: "LLDB", kind: .data, commands: ["lldb"]),
    ".swiftpm": DotInfo(what: L("Swift Package Manager settings and cache"), owner: "Swift", kind: .data, commands: ["swift"]),
    ".tor": DotInfo(what: L("Data of the Tor anonymity network"), owner: "Tor", kind: .data, apps: ["tor browser"], commands: ["tor"]),
    ".jetbrains": DotInfo(what: L("Data shared by JetBrains IDEs (IntelliJ, GoLand, PyCharm…)"), owner: "JetBrains IDE", kind: .data, apps: jetbrainsApps),
    ".jetbrains.vmoptions.sh": DotInfo(what: L("JVM options script for JetBrains IDEs, usually written by a third-party activation tool (such as ja-netfilter)"),
                                       owner: "JetBrains IDE", kind: .data, apps: jetbrainsApps, guess: true),
    ".gongfeng_copilot": DotInfo(what: L("Settings of Tencent Gongfeng Copilot, an AI coding plug-in for IDEs"), owner: "Tencent Gongfeng Copilot", kind: .data),
    ".wns": DotInfo(what: L("Data of Tencent's WNS network SDK; contains a folder of QQ Music (com.tencent.QQMusicMac)"), owner: L("QQ Music"), kind: .data,
                    apps: ["qqmusic", "qq音乐"]),
    ".grokbot": DotInfo(what: L("Settings, credentials and logs of Grok's local execution daemon"), owner: "Grok", kind: .data, apps: ["grok"],
                        commands: ["grok", "grokbot"], guess: true),
    ".jvs": DotInfo(what: L("Contains .openclaw; looks like data of OpenClaw (an AI agent)"), owner: "OpenClaw", kind: .data, apps: ["openclaw"],
                    commands: ["openclaw"], guess: true),
]

func lookupDotfile(_ name: String) -> DotInfo? {
    if let info = dotfileKB[name] { return info }
    if name.hasPrefix(".zcompdump") {
        return DotInfo(what: L("zsh completion cache, rebuilt the next time a terminal opens"), owner: "zsh", kind: .cache)
    }
    if name.hasPrefix(".v8flags") {
        return DotInfo(what: L("V8 flags cached by gulp and other Node tools"), owner: "Node tools", kind: .cache)
    }
    if name.hasSuffix("_history") || name.hasSuffix("hst") {
        return DotInfo(what: L("Input history of some command-line tool"), owner: L("Unknown"), kind: .history)
    }
    return nil
}

/// ~/Library folder names that don't match their app's name.
struct LibAlias {
    let owner: String
    var apps: [String] = []
    var commands: [String] = []
    /// Belongs to macOS itself.
    var apple = false
}

let libraryAliases: [String: LibAlias] = {
    var m = [String: LibAlias]()
    func add(_ names: [String], _ alias: LibAlias) { names.forEach { m[$0.lowercased()] = alias } }
    add(["PremiumSoft CyberTech"], LibAlias(owner: "Navicat", apps: ["navicat"]))
    add(["wpsmeeting", "WPKCaches", "wpkdata"], LibAlias(owner: "WPS Office", apps: ["wps"]))
    add(["Matrix"], LibAlias(owner: L("WeChat (Tencent's Matrix performance SDK)"), apps: ["wechat", "com.tencent.xinwechat"]))
    add(["lv", "ve"], LibAlias(owner: L("CapCut"), apps: ["capcut", "剪映", "videofusion"]))
    add(["YachData", "知音楼"], LibAlias(owner: L("Yach"), apps: ["知音楼", "yach"]))
    add(["Zhumu", "ZhumuChat"], LibAlias(owner: L("Zhumu"), apps: ["zhumu", "瞩目"]))
    add(["UmeetingChat"], LibAlias(owner: "Umeeting", apps: ["umeeting"]))
    add(["ZoomSDKChat", "ZoomPhone"], LibAlias(owner: L("Zoom or a meeting app built on Zoom"), apps: ["zoom", "zhumu", "umeeting"]))
    add(["WeComAgent", "WeComWeAgent"], LibAlias(owner: L("WeCom"), apps: ["企业微信", "wework", "wecom"]))
    add(["com.tencent"], LibAlias(owner: L("Tencent apps"), apps: ["com.tencent"]))
    add(["DingTalk", "DingTalkMac", "dinglive"], LibAlias(owner: L("DingTalk"), apps: ["dingtalk", "钉钉"]))
    add(["BaiduMacHi"], LibAlias(owner: L("Baidu Input"), apps: ["baidu"]))
    add(["baidunetdisk", "BaiduNetdisk_mac"], LibAlias(owner: L("Baidu Netdisk"), apps: ["baidunetdisk", "百度网盘"]))
    add(["Fortinet", "FortiClient"], LibAlias(owner: "FortiClient VPN", apps: ["forticlient"]))
    add(["AweSun"], LibAlias(owner: L("Sunlogin remote control"), apps: ["awesun", "向日葵", "sunlogin"]))
    add(["aDrive"], LibAlias(owner: L("Alibaba Cloud Drive"), apps: ["adrive", "阿里云盘"]))
    add(["GitKrakenCLI", "gk"], LibAlias(owner: "GitKraken", apps: ["gitkraken"], commands: ["gk"]))
    add(["Fellou", "fellou-updater"], LibAlias(owner: L("Fellou browser"), apps: ["fellou"]))
    add(["Claude"], LibAlias(owner: "Claude", apps: ["claude"], commands: ["claude"]))
    add(["Codex"], LibAlias(owner: "Codex", apps: ["codex"], commands: ["codex"]))
    add(["OpenAI"], LibAlias(owner: "ChatGPT", apps: ["chatgpt", "openai"]))
    add(["Quark"], LibAlias(owner: L("Quark"), apps: ["quark", "夸克"]))
    add(["Thunder"], LibAlias(owner: L("Xunlei"), apps: ["thunder", "迅雷"]))
    add(["Sogou", "SogouServices.binarycookies", "SogouUninstallHelper"], LibAlias(owner: L("Sogou Input"), apps: ["sogou", "搜狗"]))
    add(["ToDesk"], LibAlias(owner: "ToDesk", apps: ["todesk"]))
    add(["OKX", "okx-uuid.json"], LibAlias(owner: "OKX", apps: ["okx"]))
    add(["微信开发者工具"], LibAlias(owner: L("WeChat DevTools"), apps: ["wechatwebdevtools", "微信开发者工具"]))
    add(["Microsoft Remote Desktop Beta"], LibAlias(owner: L("Microsoft Remote Desktop"), apps: ["remote desktop", "windows app"]))
    add(["Microsoft"], LibAlias(owner: L("Microsoft apps"), apps: ["microsoft"]))
    add(["DuckDuckGo", "DuckAiNativeStorage"], LibAlias(owner: L("DuckDuckGo browser"), apps: ["duckduckgo"]))
    add(["ksfetch"], LibAlias(owner: L("Google Software Update (Chrome)"), apps: ["com.google.chrome"]))
    add(["rules"], LibAlias(owner: L("Ad-blocking rules (of some browser or proxy tool)")))
    add(["go"], LibAlias(owner: L("Go toolchain (telemetry, build cache)"), commands: ["go"]))
    add(["agora-iris.log"], LibAlias(owner: L("Agora audio/video SDK (of some meeting or streaming app)")))
    add(["KSCrash", "SentryCrash", "io.sentry", "statsig-cache", "apolloCache", "light_cache", "JetPackCache",
         "chrome_crashpad_handler", "CEF", "Chromium", "flutter_engine", "MiniLauncher", "jdyJitterMonitor", "INSTALLATION"],
        LibAlias(owner: L("An SDK built into some app (crash reporting, analytics, browser engine…)")))
    return m
}()

/// Developer-tool caches that live in ~/Library/Caches under the tool's name.
let toolCaches: [String: String] = [
    "go-build": L("Go build cache (go clean -cache)"),
    "goimports": L("Index cache of goimports, a Go editor plug-in"),
    "gopls": L("Index cache of gopls, the Go language server"),
    "ms-playwright": L("Test browsers downloaded by Playwright (downloaded again when needed)"),
    "node-gyp": L("Node headers node-gyp uses to build native modules"),
    "typescript": L("Type declaration cache of TypeScript editors"),
    "prisma-nodejs": L("Prisma engine cache"),
    "checkpoint-nodejs": L("Prisma version-check cache"),
    "js-v8flags": L("V8 flags cached by gulp and other Node tools"),
    "JNA": L("Native library cache of Java JNA"),
    "fanal": L("Cache of the Trivy image scanner"),
    "pip": L("pip download cache"),
    "Yarn": L("Yarn cache"),
    "pnpm": L("pnpm cache"),
    "CocoaPods": L("CocoaPods cache"),
    "Homebrew": L("Homebrew download cache"),
    "deno": L("Deno cache"),
    "bun": L("Bun cache"),
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
    ("org.cups.", LibAlias(owner: "macOS", apple: true)),
    ("jetbrains.iu.", LibAlias(owner: "IntelliJ IDEA", apps: ["com.jetbrains.intellij"])),
    ("jetbrains.jetprofile", LibAlias(owner: "JetBrains IDE", apps: ["jetbrains", "intellij"])),
    ("com.jetbrains.cefserver", LibAlias(owner: "JetBrains IDE", apps: ["jetbrains", "intellij"])),
    ("org.jcef.jcef", LibAlias(owner: "JetBrains IDE", apps: ["jetbrains", "intellij"])),
    ("jetbrains.vmoptions", LibAlias(owner: L("JetBrains IDE (third-party activation tool)"), apps: ["jetbrains", "intellij"])),
    ("jetbrains.db.", LibAlias(owner: "DataGrip", apps: ["datagrip"])),
    ("com.jetbrains.datagrip", LibAlias(owner: "DataGrip", apps: ["datagrip"])),
    ("com.jetbrains.goland", LibAlias(owner: "GoLand", apps: ["goland"])),
    ("com.electron.dockerdesktop", LibAlias(owner: "Docker", apps: ["com.docker.docker"])),
    ("com.ebus.lark", LibAlias(owner: L("Lark"), apps: ["com.electron.lark"])),
    ("com.prect.navicat", LibAlias(owner: "Navicat", apps: ["navicat"])),
    ("codex-runtimes", LibAlias(owner: "Codex", apps: ["codex", "cursor"], commands: ["codex"])),
    ("github-copilot", LibAlias(owner: L("GitHub Copilot (editor plug-in)"), apps: ["cursor", "visual studio code", "intellij"])),
    ("com.tencent.rqd", LibAlias(owner: L("Crash-reporting SDK built into Tencent apps"))),
    ("com.tencent.bugly", LibAlias(owner: L("Crash-reporting SDK built into Tencent apps"))),
    ("com.tencent.tds.bugly", LibAlias(owner: L("Crash-reporting SDK built into Tencent apps"))),
    ("com.tencent.fireeye", LibAlias(owner: L("Crash-reporting SDK built into Tencent apps"))),
]

func libraryAlias(for id: String) -> LibAlias? {
    let lower = id.lowercased()
    return libraryAliases[lower] ?? libraryPrefixAliases.first { lower.hasPrefix($0.prefix) }?.alias
}
