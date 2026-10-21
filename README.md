# MacTidy

**English** · [简体中文](README.zh-CN.md)

A read-only catalog of everything on a Mac that has been migrated from one machine to the next for years.

**[Download the latest version](https://github.com/chrions/MacTidy/releases/latest)** · macOS 14+ · Apple silicon · free and open source

Migration Assistant brings everything along: apps you stopped using three Macs ago, the data they left behind, old Intel toolchains, launch agents of uninstalled software, keys and histories in your home folder. MacTidy takes stock of all of it, like a librarian, and answers three questions for each thing:

- **Who owns it?** Which app, tool or system feature it belongs to, or that the owner is gone.
- **Which Mac did it come from?** Every Mac you migrated from leaves a folder in `~/Library/Keychains`. MacTidy uses their creation dates to split your history into eras, and files each thing under the era of its oldest file.
- **Have you used it since moving here?** It checks Spotlight's last-opened dates, data-folder changes and your shell history.

Things you're unsure about can go to **cold storage** first: they're moved aside with their original locations recorded, and can be put back in one click.

![Overview: eras inferred from migrations, and the catalog by category](docs/screenshots/overview.png)

![A shelf: everything that belongs to the Go toolchain, where each part came from, and what hasn't been used](docs/screenshots/shelf.png)

![Freezing an unused item, then putting it back from cold storage in one click](docs/screenshots/freeze-and-put-back.gif)

## Features

- **Shelves by category**: System, Apps, Development (Homebrew, Node, Go, Python, Ruby, Java, Rust…), Terminal (shell config, command-line tools, keys, histories), My Files, and Orphans.
- **Era inference** from migration traces. You can rename each era, e.g. "Intel MacBook from work".
- **"Not used since arriving"** filter, so you see what came over in a migration and was never touched again.
- **Keep, Freeze, or Move to Trash**, per item or per shelf. Freezing moves things to `~/MacTidy Cold Storage` with a manifest. Trashed items can be put back until the Trash is emptied.
- **Built-in knowledge base** for common apps, SDK leftovers, dotfiles and version managers (nvm, pyenv, rbenv, n, old Intel Homebrew…).
- **Optional AI recognition** for things the knowledge base doesn't know, using any OpenAI-compatible endpoint (OpenAI, DeepSeek, Qwen, Kimi, Zhipu GLM, or a local Ollama).
- **Languages**: English, 简体中文, 日本語, 한국어. You can switch in Settings.

## Safety and privacy

- **The scan is read-only.** Nothing changes until you click Freeze or Move to Trash, and both can be undone.
- **macOS itself is left alone.** Anything on the sealed system volume or belonging to Apple is shown for reference only.
- **Things are never deleted outright**; they only go to the Trash.
- **AI recognition is opt-in.** It sends only names, paths (with your home folder written as `~`), kinds, sizes and dates. File contents are never read. Items named like ID documents, contracts or keys aren't sent at all. Numbers of 7 or more digits are masked, and you can add your own words to never send. The API key is stored in your keychain.

## Download

Requires macOS 14 Sonoma or later on Apple silicon.

1. Download `MacTidy-<version>.zip` from the [latest release](https://github.com/chrions/MacTidy/releases/latest), unzip it, and move `MacTidy.app` to Applications.
2. Open it for the first time. MacTidy isn't notarized by Apple yet, so macOS will say it can't verify the developer.
   - **macOS 15 Sequoia and later**: click Done, then go to System Settings → Privacy & Security, scroll down, and click **Open Anyway** next to MacTidy.
   - **macOS 14 Sonoma**: right-click `MacTidy.app`, choose **Open**, then click **Open** again.
   - Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/MacTidy.app`
3. For a complete catalog, grant MacTidy **Full Disk Access** in System Settings → Privacy & Security. Without it, some apps' data is listed by name only.

If you'd rather not trust a downloaded binary, build it yourself, as described below. It only takes a minute.

## Build from source

You need Xcode or the Command Line Tools (`xcode-select --install`), and Swift 5.9 or later.

```sh
git clone https://github.com/chrions/MacTidy.git
cd MacTidy
./build.sh
```

`build.sh` compiles the app with `swiftc` (there is no Xcode project), installs it in `/Applications` and opens it.

It also signs the app with a self-signed identity kept in its own keychain (`~/Library/Keychains/mactidy-signing.keychain-db`). That way the Full Disk Access permission survives rebuilds; an ad-hoc signature changes on every build and silently invalidates the permission.

`./build.sh release` builds the same app without installing it and packages it as `build/MacTidy-<version>.zip`.

### Command-line tool

```sh
./build.sh cli
./build/mactidy --out ./reports
```

This prints a summary and writes the full catalog as `catalog-<time>.md` and `catalog-<time>.json`. It also refreshes the catalog the app shows.

## Where things are stored

| What | Where |
| --- | --- |
| Catalog, era names, decisions, AI settings and notes, trash log | `~/Library/Application Support/MacTidy` |
| Cold storage | `~/MacTidy Cold Storage` |
| AI API key | Your login keychain |

## Translating

The English text in the source code is the key. Translations live in `Tools/translations/<language>.json`.

```sh
python3 Tools/l10n.py           # report missing or mismatched translations
python3 Tools/l10n.py --write   # regenerate Resources/<language>.lproj
```

To add a language:

1. Copy `zh-Hans.json` to `<code>.json` and translate the values, keeping the `%@` and `%lld` placeholders.
2. Add the code to `LANGS` in `Tools/l10n.py`.
3. Add the code to `CFBundleLocalizations` in `Resources/Info.plist`.
4. Add the code to the language list in `Sources/App/SettingsView.swift`.

## Project layout

```
Sources/Core   scanning, era inference, knowledge base, cold storage, AI client
Sources/App    SwiftUI app
Sources/CLI    command-line tool
Resources      Info.plist, icon, generated translations
Tools          translation script, icon generator
```

## License

[MIT](LICENSE)
