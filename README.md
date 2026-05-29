# PaperInbox

PaperInbox is a native macOS menu-bar app for tracking papers locally, organizing them into collections, launching ChatGPT with structured prompts, and importing wrapped ChatGPT outputs back into the local library.

This repository currently uses Swift Package layout plus a manual app-bundle build script because this machine has Command Line Tools but not full Xcode.

## From Scratch

Clone the repository:

```sh
git clone <github-repo-url>
cd paper_inbox_project
```

Check that Swift is available:

```sh
swift --version
```

PaperInbox is a native macOS app. You need either full Xcode or Apple's Command Line Tools installed. This repo currently includes a manual app-bundle build path that works with Command Line Tools.

Build the app bundle:

```sh
make app
```

That creates:

```text
Build/PaperInbox.app
```

Run it from the build folder by opening `Build/PaperInbox.app`, or install it into Applications:

```sh
cp -R Build/PaperInbox.app /Applications/
```

Then launch:

```text
/Applications/PaperInbox.app
```

PaperInbox is a menu-bar app, so look for the small inbox icon in the macOS menu bar after launch.

## Build

The local build path that works in this environment is:

```sh
make app
```

That creates:

```text
Build/PaperInbox.app
```

## Install After Rebuilding

After building, quit PaperInbox if it is already running, then copy the app bundle into `/Applications`:

```sh
cp -R Build/PaperInbox.app /Applications/
```

You can also drag `Build/PaperInbox.app` into the Applications folder in Finder.

Launch the installed app from:

```text
/Applications/PaperInbox.app
```

PaperInbox stores its local database and copied PDFs under `~/Library/Application Support/PaperInbox/`, so moving the app bundle does not move or delete your library data.

You can also typecheck the app and core sources without building a bundle:

```sh
make typecheck
```

On a machine with full Xcode or a repaired Command Line Tools install, the SwiftPM commands should be:

```sh
swift build
swift test
```

On this machine, `swift test` currently fails before compiling project code because `xcrun --sdk macosx --show-sdk-platform-path` fails for the active Command Line Tools installation.

## Implemented

- Menu-bar app shell with PaperInbox menu.
- Library window with sidebar, paper list, and paper detail panes.
- Local SQLite database using the system SQLite library.
- FTS5 search table for paper metadata and imported artifact text.
- Local storage under `~/Library/Application Support/PaperInbox/`.
- Add URL papers.
- Add PDF papers and copy them into app storage.
- Best-effort metadata extraction for new PDFs and online metadata lookup for paper URLs.
- Paper IDs in `P-YYYY-MM-DD-NNNN` format.
- Collections with create/delete and paper assignment.
- Status tracking for unread, to study, read, and archived.
- Artifact indicators for summary, study guide, and chat transcript availability.
- Read/archived visibility behavior.
- PDF reveal and source URL open actions.
- Exact summary and study-guide prompt generation.
- Copy prompt and best-effort ChatGPT app open.
- Clipboard wrapper parser/import for summaries and study guides.
- Markdown mirroring for imported artifacts.
- Scrollable rendered artifact view for imported Markdown and LaTeX/math content.
- Saved ChatGPT conversation link field on summary and study-guide sections, even before content is imported.

## Not Yet Implemented

- Xcode project scaffolding.
- Automatic prompt paste via Accessibility.
- Automatic PDF attachment.
- ChatGPT export ZIP import and review UI.
- Editable prompt templates.
- Open-at-login setting.
