# Building, Code Signing & Distribution

This guide covers how to build an installable `.app` bundle, configure Apple Code Signing, notarize the package for Gatekeeper, and create release distributions.

---

## 1. Building with Xcode (Recommended)

Because ProPack is built using native SwiftUI and modern Swift 6 macros (`@Observable`), **Xcode 15 or 16+** provides the complete toolchain (compiler, asset catalog compiler `actool`, macro plugins, and linker).

### Steps in Xcode

1. Open `ProPack.xcodeproj` in Xcode:
   ```bash
   open ProPack.xcodeproj
   ```
2. In the scheme selector (top bar), choose **ProPack > My Mac**.
3. Select **Product ▸ Archive** from the menu bar.
4. When the Organizer window opens:
   - Click **Distribute App**.
   - Choose your distribution method:
     - **Direct Distribution (Developer ID)**: For distributing outside the Mac App Store.
     - **Development / Copy App**: For testing on your local machine.
5. Export the archive to get your standalone `ProPack.app`.

To install it locally:
```bash
cp -R /path/to/exported/ProPack.app /Applications/
```

---

## 2. Code Signing: Making It "Just Work"

macOS Gatekeeper blocks or warns against running unsigned binaries downloaded from the internet. Depending on your distribution goals, there are three tiers of code signing:

```
┌────────────────────────────────────────────────────────────────────────┐
│ Tier 1: Local Development (Ad-Hoc Signing)                             │
│   • Identity: "-" (Ad-Hoc)                                             │
│   • Works on: Your own Mac                                             │
│   • Cost: Free                                                         │
├────────────────────────────────────────────────────────────────────────┤
│ Tier 2: Distribution to Other Macs (Apple Developer ID + Notarization) │
│   • Identity: "Developer ID Application: <Name> (<Team ID>)"           │
│   • Works on: Any Mac without Gatekeeper warnings                      │
│   • Cost: Apple Developer Program ($99/year)                           │
├────────────────────────────────────────────────────────────────────────┤
│ Tier 3: Mac App Store                                                  │
│   • Identity: "Apple Distribution: <Name> (<Team ID>)"                 │
│   • Requires: App Sandbox (Note: ProPack requires lsof process         │
│     inspection which necessitates non-sandboxed Developer ID).         │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Step-by-Step: Signing with an Apple Developer Account

To distribute ProPack to team members or users so it **opens immediately with zero warnings**:

### Step A: Obtain a Developer ID Certificate

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/).
2. In Xcode, open **Settings ▸ Accounts** (`Cmd + ,`).
3. Add your Apple ID.
4. Select your Team and click **Manage Certificates...**.
5. Click **+ ▸ Developer ID Application**. Xcode will generate and install the certificate in your macOS Keychain.
6. Verify your certificate in Terminal:
   ```bash
   security find-identity -p codesigning -v
   ```
   You will see an entry like:
   ```
   1) 1234567890ABCDEF1234567890ABCDEF12345678 "Developer ID Application: Your Name (TEAMID)"
   ```

### Step B: Enable Hardened Runtime & Signing in Xcode

1. In Xcode, select the **ProPack** project in the navigator.
2. Under **Targets ▸ ProPack ▸ Signing & Capabilities**:
   - Check **Automatically manage signing**.
   - Set **Team** to your developer team.
   - Set **Bundle Identifier** to your domain (e.g., `com.yourdomain.propack`).
   - Notice **Hardened Runtime** is enabled (configured in `project.pbxproj`).
3. Verify that `Config/ProPack.entitlements` has:
   ```xml
   <key>com.apple.security.app-sandbox</key>
   <false/>
   ```
   *(ProPack intentionally does not use App Sandbox because `/usr/sbin/lsof` must inspect ProPresenter's sockets).*

### Step C: Manual Code Signing via Terminal

If you build via command line (`xcodebuild`), you can sign the built bundle using `codesign`:

```bash
codesign --force --deep \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  --options runtime \
  --entitlements Config/ProPack.entitlements \
  dist/ProPack.app
```

Verify the signature:
```bash
codesign --verify --deep --strict --verbose=2 dist/ProPack.app
spctl --assess --type execute --verbose dist/ProPack.app
```

---

## 4. Notarization (Apple Notary Service)

Signing with a Developer ID is step 1; Apple also requires **Notarization** for apps distributed outside the Mac App Store on macOS 10.15+. Without notarization, Gatekeeper displays a *"cannot check it for malicious software"* dialog.

### Automated via Xcode
When exporting from Xcode Organizer (**Product ▸ Archive ▸ Distribute App ▸ Direct Distribution**), select **Upload** to automatically submit to Apple's notary service. Xcode automatically staples the notarization ticket to the `.app`.

### Command Line via `notarytool`

1. Store your App Store Connect credentials in the Keychain:
   ```bash
   xcrun notarytool store-credentials "propack-notary" \
     --apple-id "you@example.com" \
     --team-id "TEAMID" \
     --password "xxxx-xxxx-xxxx-xxxx" # App-specific password
   ```
2. Create a zip archive of the app:
   ```bash
   ditto -c -k --keepParent ProPack.app ProPack.zip
   ```
3. Submit for notarization:
   ```bash
   xcrun notarytool submit ProPack.zip \
     --keychain-profile "propack-notary" \
     --wait
   ```
4. Once accepted, staple the ticket:
   ```bash
   xcrun stapler staple ProPack.app
   ```

---

## 5. Local / Internal Testing (Without a Paid Apple Developer Account)

If you are only running ProPack on your own Mac or machines you control:

### 1. Ad-Hoc Signing (Default in ProPack)
ProPack's build settings are already configured with `CODE_SIGN_IDENTITY = "-"` (Ad-Hoc). An ad-hoc signed app runs without issue on the Mac that built it.

### 2. If macOS Gatekeeper Blocks an App Downloaded from GitHub/Slack
If a colleague downloads an ad-hoc signed `.app` bundle from the web, macOS will set the quarantine flag:
```bash
# To allow the app to run without Gatekeeper blocking it:
xattr -cr /Applications/ProPack.app
```
Alternatively, right-click the app in Finder and choose **Open**, then click **Open** in the confirmation dialog.
