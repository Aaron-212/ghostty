"""
This script is used to update the appcast.xml file for Ghostty releases.
The script is currently hardcoded to only work for tip releases and therefore
doesn't have rich release notes, hardcodes the URL to the tip bucket, etc.

This expects the following files in the current directory:
    - sign_update.txt - contains the output from "sign_update" in the Sparkle
      framework for the current build.
    - appcast.xml - the existing appcast file.

And the following environment variables to be set:
    - GHOSTTY_BUILD - the build number
    - GHOSTTY_COMMIT - the commit hash

The script will output a new appcast file called appcast_new.xml.
"""

import os
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

now = datetime.now(timezone.utc)
build = os.environ["GHOSTTY_BUILD"]
commit = os.environ["GHOSTTY_COMMIT"]

# Read our sign_update output
with open("sign_update.txt", "r") as f:
    # format is a=b b=c etc. create a map of this. values may contain equal
    # signs, so we can't just split on equal signs.
    attrs = {}
    for pair in f.read().split(" "):
        key, value = pair.split("=", 1)
        value = value.strip()
        if value[0] == '"':
            value = value[1:-1]
        attrs[key] = value

# We need to register our namespaces before reading or writing any files.
ET.register_namespace("sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")

# Open our existing appcast and find the channel element. This is where
# we'll add our new item.
et = ET.parse('appcast.xml')
channel = et.find("channel")

# Create the item using some absoultely terrible XML manipulation.
item = ET.SubElement(channel, "item")
elem = ET.SubElement(item, "title")
elem.text = f"Build {build}"
elem = ET.SubElement(item, "pubDate")
elem.text = now.strftime("%a, %d %b %Y %H:%M:%S %z")
elem = ET.SubElement(item, "sparkle:version")
elem.text = build
elem = ET.SubElement(item, "sparkle:shortVersionString")
elem.text = commit
elem = ET.SubElement(item, "sparkle:minimumSystemVersion")
elem.text = "12.0.0"
elem = ET.SubElement(item, "description")
elem.text = f"""
<p>Automated build from commit <code>{commit}</code>.</p>
<p>
These are automatic per-commit builds generated from the main Git branch.
We do not generate any release notes for these builds. You can view the full
commit history
<a href="https://github.com/mitchellh/ghostty">on GitHub</a> for all changes.
</p>
"""
elem = ET.SubElement(item, "enclosure")
elem.set("url", f"https://tip.files.ghostty.dev/{build}/ghostty-macos-universal.zip")
elem.set("type", "application/octet-stream")
for key, value in attrs.items():
    elem.set(key, value)

# Output the new appcast.
et.write("appcast_new.xml", xml_declaration=True, encoding="utf-8")
