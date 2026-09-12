cask "potenad" do
  version :latest
  sha256 :no_check

  url "https://github.com/robertmorelli/potenad/releases/latest/download/PoteNad-macOS.dmg"
  name "PoteNad"
  desc "Small native plain-text editor"
  homepage "https://github.com/robertmorelli/potenad"

  depends_on macos: :ventura

  app "PoteNad.app"

  zap trash: "~/Library/Preferences/com.robertmorelli.notepad.plist"
end
