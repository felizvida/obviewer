# Installing Obviewer

Obviewer is a read-only reader for Markdown files, Obsidian vaults and DokuWiki folders on Apple silicon Macs with **macOS 26 or later**. These steps cover the **ad-hoc signed** build published on GitHub Releases. It isn't notarized by Apple (the project has no Apple Developer ID yet), so macOS asks you to approve it once.

> Version 0.3.0 has been tested on one Mac running macOS 26 on Apple silicon. Installing on other Macs hasn't been verified yet. Please report what happens.
>
> **Older macOS:** from the next release on, Obviewer requires macOS 26. `v0.3.0-beta.1` and `v0.3.0-beta.2` declared macOS 14 as their minimum but were only ever run on macOS 26.
>
> **Intel Macs:** from `v0.3.0-beta.2` on, Obviewer is built for Apple silicon only. `v0.3.0-beta.1` is a universal build that remains available, but it has never been run on an Intel Mac.

## Install

1. Download `Obviewer-<version>-macOS-adhoc.dmg` from the project's [GitHub Releases](https://github.com/felizvida/obviewer/releases) page. Optionally, compare its SHA-256 with the `-dmg-sha256.txt` file next to it (`shasum -a 256 <file>`).
2. Open the DMG and drag **Obviewer** onto **Applications**.
3. Open **Applications** and double-click **Obviewer**. macOS says it can't verify the app. Click **Done** (or **Cancel**).
4. Open **System Settings › Privacy & Security**, scroll to the message about Obviewer, and click **Open Anyway**. Confirm with your password or Touch ID. This is a deliberate trust decision; Apple explains it in [Open a Mac app from an unknown developer](https://support.apple.com/en-us/102445).
5. Obviewer opens. After that it usually starts normally, until you install an update (see below).

If your Mac is managed by an IT department and step 4 doesn't offer **Open Anyway**, the device policy blocks apps that Apple hasn't notarized. Ask your IT contact.

## Open your notes

- **A vault or folder:** choose **File › Open File or Folder…** (⌘O) and pick the folder. Obviewer reopens it at the next launch.
- **One file:** double-click a `.md` file once Obviewer is your Markdown app (see below), or drag it onto the Dock icon. If the note shows images or links to notes stored next to it, a banner offers **Allow Access…**, which grants read-only access to that folder.
- **DokuWiki:** open the wiki's install folder or its `data` folder. Pages are found under `data/pages` and media under `data/media`.

## Make it your Markdown viewer (optional)

- **Double-click to open:** select a `.md` file in Finder and choose **File › Get Info**. Under **Open with**, choose **Obviewer**, then click **Change All…**.
- **Quick Look:** select a Markdown file and press **Space**. The preview is a static rendering: diagrams appear as source text and images as placeholders. If you see plain text instead, open Obviewer once, then check that its Quick Look extension is enabled:
  System Settings › General › Login Items & Extensions, under Quick Look.

## Updating

Install a new version the same way, replacing the old copy in **Applications**. Each ad-hoc build has a new signature, and macOS treats a new signature as a possibly different app. So it may:

- **Ask again whether to open the app.** Approve it as in step 4, if the download is one you trust (compare the checksum).
- **Ask whether Obviewer may "access data from other apps".** The data in question is Obviewer's own container: its settings, recent items and index cache. Allowing keeps them. Denying starts Obviewer fresh, with no effect on your notes. Only allow it for a build you downloaded from the project's releases.
- **Forget folder access.** Reopen your vault with ⌘O.

These effects haven't been tested on a second Mac yet.

## What Obviewer does and doesn't do with your files

**Your notes are read-only, and macOS enforces it.** The app runs in the App Sandbox, and its only file permission is read-only access to files and folders you choose. The operating system rejects any attempt to change them, whatever the app's code does.

Obviewer does write in two places, neither of them your notes:

- its own private container (`~/Library/Containers/com.felizvida.obviewer`), for settings, the index cache and temporary PDFs
- the clipboard, when you copy

**Other apps you hand a note to aren't covered.** Edit in…, opening an attachment, Preview, and share-sheet services run outside Obviewer's sandbox and can change or send files as they normally would. Web links open in your browser. Obviewer asks first before opening attachments or links that start another app (such as `obsidian://`), and it never opens apps, installers or scripts from a note.

**Network.** On our test Mac, Apple's WebKit, which draws the notes, wouldn't start inside the sandbox without the "outgoing network connections" permission, so Obviewer holds it. Obviewer itself makes no network requests. The reader blocks every load that isn't a bundled file or a file from your folder, including images linked from the web, and it refuses to show notes if that blocking can't be switched on. This protection is enforced by Obviewer, not by macOS. The Quick Look preview has no network permission at all. Obviewer can't accept incoming connections.

## Editing

Press **⌘E** (**Edit in…**). The note opens in **Sublime Text** if you have it, and Obviewer shows your changes each time you save. With the default **Automatic** setting, and no Sublime Text installed, Obviewer uses:

1. the file's default app, unless that's Obviewer itself or Spyder
2. otherwise the first one installed of: CotEditor, BBEdit, Visual Studio Code, Cursor, Zed, Typora, iA Writer, MarkText, TextEdit

Obsidian is used only if you choose it in **Settings › Editing**, where you can also pick any other app.

## Sharing a note

- **Copy as Rich Text** (⌥⌘C) for Mail and Word. Headings, lists, links, tables and diagrams come across. Local images become "[image: …]" placeholders.
- **Copy for Slack** (⇧⌘C). Text, code and tables come across, but Slack currently turns headings and bold into italics and flattens nested bullets.
- **Open as PDF in Preview** (⌥⌘P) makes a PDF and opens it in Preview; save it from there with **File › Export as PDF…**. The print dialog's own "Save as PDF" doesn't work in Obviewer, because it needs permission to write files. Use ⌥⌘P, or the dialog's PDF menu › **Open in Preview**.
- **Share › Share as PDF…** for Mail, Messages or AirDrop. **Print…** (⌘P) for paper.

## Uninstall

Drag **Obviewer** from **Applications** to the Trash. Its settings and cache live in `~/Library/Containers/com.felizvida.obviewer`, which you can delete too.
