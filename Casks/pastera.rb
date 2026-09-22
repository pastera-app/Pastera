cask "pastera" do
  version "3.0.6-beta"
  sha256 "797c95ee3c7ccc8d79a6e6ffe8fdcc2e0ce2d3f96514f128e242bed170c4e3d1"

  url "https://github.com/pastera-app/Pastera/releases/download/v#{version}/Pastera-#{version}-macOS.dmg",
      verified: "github.com/pastera-app/Pastera/"
  name "Pastera"
  desc "Clipboard manager with history, snippets, and keyboard shortcuts"
  homepage "https://github.com/pastera-app/Pastera"

  livecheck do
    url "https://github.com/pastera-app/Pastera"
    regex(/^v?(\d+(?:\.\d+)+-beta)$/i)
    strategy :github_releases
  end

  depends_on macos: ">= :sequoia"

  app "Pastera.app"

  uninstall quit: "com.pastera-app.Pastera"

  zap trash: [
    "~/Library/Application Support/Pastera",
    "~/Library/Caches/com.pastera-app.Pastera",
    "~/Library/HTTPStorages/com.pastera-app.Pastera",
    "~/Library/Preferences/com.pastera-app.Pastera.plist",
    "~/Library/Saved Application State/com.pastera-app.Pastera.savedState",
  ]

  caveats <<~EOS
    Pastera is currently distributed as an unsigned beta DMG. macOS Gatekeeper
    may require you to approve the app manually from Privacy & Security before
    it can be opened.

    Automatic Paste is disabled by default. Enable it from Pastera > Settings >
    General only if you want Pastera to send Command+V after choosing an item;
    macOS will then ask for Accessibility permission.
  EOS
end
