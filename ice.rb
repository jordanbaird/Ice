# Documentation: https://docs.brew.sh/Cask-Cookbook
#                https://docs.brew.sh/Adding-Software-to-Homebrew#cask-stanzas
# PLEASE REMOVE ALL GENERATED COMMENTS BEFORE SUBMITTING YOUR PULL REQUEST!
cask "ice" do
  version "0.5.0"
  sha256 "f9c22913aab605e4e378a7e784261466cb3f9bcf45862796b6a26c58d05a2df7"

  url "https://github.com/jordanbaird/Ice/releases/download/#{version}/Ice.zip"
  name "Ice"
  desc "Ice Powerful menu bar manager for macOS"
  homepage "https://github.com/jordanbaird/Ice"

  depends_on macos: ">= :sonoma"
  app "Ice.app"
end
