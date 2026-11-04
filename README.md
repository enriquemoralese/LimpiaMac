# iClear

A Mac app that finds what takes up space for nothing and moves it to the Trash only when you approve.

Works on Apple silicon and Intel Macs with macOS 14 or later.

## Download

1. Download **[iClear.zip](https://github.com/enriquemoralese/iClear/releases/latest/download/iClear.zip)** and open it.
2. Drag **iClear** to your **Applications** folder.
3. The first time, **right-click › Open** and confirm. If macOS won't let you, go to **System Settings › Privacy & Security** and click **Open Anyway**.
4. Let it read the whole disk: in **System Settings › Privacy & Security › Full Disk Access**, add iClear. Without this, the scan is incomplete.

macOS shows the warning in step 3 because the app isn't signed with an Apple developer account. That's normal for apps outside the App Store.

## Use

1. Click **Scan**.
2. Review each category. Click a file to see it large.
3. Check what you want to remove and click **Move to Trash**.

Nothing is permanently deleted until you empty the Trash.

## Protect your folders

In **iClear › Settings** (⌘,) add the folders the app must never touch, like your important documents or projects. Do it before your first scan.

## Build it yourself

You need Apple's developer tools (`xcode-select --install`). In Terminal:

```
git clone https://github.com/enriquemoralese/iClear.git
cd iClear
./empaquetar.sh
mv iClear.app /Applications/
```

Tests: `swift test` (logic, with fake folders) and `Scripts/pruebas_ui.sh` (the real app; scans your home folder without moving anything).
