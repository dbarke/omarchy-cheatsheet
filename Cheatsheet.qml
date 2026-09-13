import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Staged keybinding cheat sheet.
//
// tiers.json only names bindings by their description; the actual keys are
// read from `omarchy-menu-keybindings --print` every time the sheet opens, so
// a rebind shows up here without touching this plugin. Entries whose binding
// no longer exists are left out rather than shown with stale keys.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  property string learnedPath: Quickshell.env("HOME") + "/.local/state/omarchy/cheatsheet-learned.json"
  property var shell: null
  property var manifest: null

  property bool opened: false
  property var tiers: []
  property var bindings: ({})   // description -> [{ mods: [...], key: "..." }]
  property var herdrKeys: ({})  // herdr action -> ["prefix+x", "alt+esc"]
  property string herdrPrefix: ""
  property var learned: ({})    // description (or "herdr:<action>") -> true
  property int tierIndex: 0
  property int selectedIndex: -1
  property bool hideLearned: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.menu.selectedText
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int pad: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(1080), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  property int columns: cardWidth > Style.space(760) ? 2 : 1
  property int rowHeight: Math.max(Style.space(52), Style.font.title + Style.font.bodySmall + Style.spacing.xl * 2)

  readonly property var keyNames: ({
    "SUPER": "Super", "SHIFT": "Shift", "CTRL": "Ctrl", "ALT": "Alt",
    "RETURN": "Enter", "ESCAPE": "Esc", "SPACE": "Space", "TAB": "Tab",
    "BACKSPACE": "Backspace", "PRINT": "PrtSc", "DELETE": "Del",
    "LEFT": "←", "RIGHT": "→", "UP": "↑", "DOWN": "↓",
    "COMMA": ",", "PERIOD": ".", "MINUS": "-", "EQUAL": "=", "SLASH": "/",
    "LEFT MOUSE BUTTON": "Left drag", "RIGHT MOUSE BUTTON": "Right drag"
  })

  function open(payloadJson) {
    root.opened = true
    root.selectedIndex = -1
    bindingsProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "dbarke.cheatsheet")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function prettyKey(k) {
    return root.keyNames[k] !== undefined ? root.keyNames[k] : k
  }

  // "SUPER SHIFT + RETURN   → Browser" -> bindings["Browser"] += { mods, key }
  function parseBindings(text) {
    var out = ({})
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("→")
      if (parts.length < 2) continue
      var combo = parts[0].trim()
      var desc = parts.slice(1).join("→").trim()
      if (!combo || !desc) continue
      var plus = combo.indexOf(" + ")
      var mods = plus === -1 ? [] : combo.slice(0, plus).split(/\s+/)
      var key = plus === -1 ? combo : combo.slice(plus + 3)
      if (!out[desc]) out[desc] = []
      out[desc].push({ mods: mods, key: key })
    }
    root.bindings = out
    root.rebuild()
  }

  // The [keys] table of herdr's config.toml: `action = "spec"` or
  // `action = ["spec", "spec"]`. Actions left at herdr's defaults aren't in
  // the file, so entries naming them stay hidden like missing Hyprland binds.
  function parseHerdrKeys(text) {
    var out = ({})
    var prefix = ""
    var inKeys = false
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line.charAt(0) === "[" && line.indexOf("=") === -1) { inKeys = line === "[keys]"; continue }
      if (!inKeys) continue
      var m = line.match(/^([a-z_]+)\s*=\s*(.+)$/)
      if (!m) continue
      var specs = []
      var re = /"([^"]*)"/g
      var s
      while ((s = re.exec(m[2])) !== null) specs.push(s[1])
      if (specs.length === 0) continue
      if (m[1] === "prefix") prefix = specs[0]
      else out[m[1]] = specs
    }
    root.herdrPrefix = prefix
    root.herdrKeys = out
    root.rebuild()
  }

  function prettyHerdrKey(k) {
    if (k === "1..9") return "1 … 9"
    var up = k.toUpperCase()
    if (root.keyNames[up] !== undefined) return root.keyNames[up]
    if (up === "ENTER") return "Enter"
    if (up === "ESC") return "Esc"
    return k.length === 1 ? up : k.charAt(0).toUpperCase() + k.slice(1)
  }

  // "prefix+shift+k" -> [["Ctrl+Space"], ["Shift", "K"]]: the prefix chord is
  // one cap, pressed and released before the rest.
  function herdrCombos(spec, keyOverride) {
    var parts = spec.split("+")
    var combos = []
    if (parts[0] === "prefix") {
      combos.push([root.herdrPrefix ? root.herdrPrefix.split("+").map(root.prettyHerdrKey).join("+") : "Prefix"])
      parts = parts.slice(1)
    }
    var caps = parts.map(root.prettyHerdrKey)
    if (keyOverride) caps[caps.length - 1] = keyOverride
    combos.push(caps)
    return combos
  }

  function loadTiers(text) {
    try { root.tiers = JSON.parse(text) } catch (e) { root.tiers = [] }
    root.rebuild()
  }

  function loadLearned(text) {
    try { root.learned = JSON.parse(text) || ({}) } catch (e) { root.learned = ({}) }
    root.rebuild()
  }

  function saveLearned() {
    learnedFile.setText(JSON.stringify(root.learned, null, 2) + "\n")
  }

  // Resolved entries for one tier: keys joined in, missing bindings dropped.
  function resolvedEntries(tier) {
    var out = []
    var entries = (tier && tier.entries) || []
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (e.herdr) {
        var specs = root.herdrKeys[e.herdr]
        if (!specs) continue
        // "chord": true prefers a binding that skips the prefix (alt+right
        // over prefix+n), falling back to the first one listed.
        var spec = specs[0]
        if (e.chord) {
          for (var c = 0; c < specs.length; c++) {
            if (specs[c].indexOf("prefix+") !== 0) { spec = specs[c]; break }
          }
        }
        out.push({ desc: "herdr:" + e.herdr, label: e.label || e.herdr, hint: e.hint || "", combos: root.herdrCombos(spec, e.key) })
        continue
      }
      var found = root.bindings[e.desc]
      if (!found || found.length === 0) continue
      // One combo per entry: the first one listed is the primary binding
      // (Browser, for one, has a second key that would only add noise).
      var caps = []
      for (var m = 0; m < found[0].mods.length; m++) caps.push(root.prettyKey(found[0].mods[m]))
      caps.push(e.key || root.prettyKey(found[0].key))
      var combos = [caps]
      out.push({ desc: e.desc, label: e.label || e.desc, hint: e.hint || "", combos: combos })
    }
    return out
  }

  function learnedCount(tier) {
    var entries = root.resolvedEntries(tier)
    var n = 0
    for (var i = 0; i < entries.length; i++) if (root.learned[entries[i].desc]) n++
    return { learned: n, total: entries.length }
  }

  function rebuild() {
    entryModel.clear()
    var entries = root.resolvedEntries(root.tiers[root.tierIndex])
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      if (root.hideLearned && root.learned[e.desc]) continue
      entryModel.append({ desc: e.desc, label: e.label, hint: e.hint, combosJson: JSON.stringify(e.combos) })
    }
    if (root.selectedIndex >= entryModel.count) root.selectedIndex = entryModel.count - 1
  }

  function setTier(index) {
    if (root.tiers.length === 0) return
    root.tierIndex = (index + root.tiers.length) % root.tiers.length
    root.selectedIndex = -1
    root.rebuild()
  }

  function toggleLearned(index) {
    if (index < 0 || index >= entryModel.count) return
    var desc = entryModel.get(index).desc
    var next = ({})
    for (var k in root.learned) next[k] = root.learned[k]
    if (next[desc]) delete next[desc]
    else next[desc] = true
    root.learned = next
    root.saveLearned()
    root.rebuild()
  }

  function move(delta) {
    if (entryModel.count === 0) return
    if (root.selectedIndex < 0) root.selectedIndex = delta < 0 ? entryModel.count - 1 : 0
    else root.selectedIndex = Math.max(0, Math.min(entryModel.count - 1, root.selectedIndex + delta))
    grid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  ListModel { id: entryModel }

  Process {
    id: bindingsProc
    command: [root.omarchyPath + "/bin/omarchy-menu-keybindings", "--print"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseBindings(text)
    }
  }

  FileView {
    path: root.pluginDir + "tiers.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadTiers(text())
    onFileChanged: reload()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.config/herdr/config.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.parseHerdrKeys(text())
    onFileChanged: reload()
  }

  FileView {
    id: learnedFile
    path: root.learnedPath
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadLearned(text())
    onLoadFailed: root.loadLearned("{}")
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "dbarke-cheatsheet"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.pad

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          var k = event.key
          if (k === Qt.Key_Escape || k === Qt.Key_F1 || k === Qt.Key_Q) root.dismiss()
          else if (k >= Qt.Key_1 && k <= Qt.Key_9) root.setTier(k - Qt.Key_1)
          else if (k === Qt.Key_Tab) root.setTier(root.tierIndex + 1)
          else if (k === Qt.Key_Backtab) root.setTier(root.tierIndex - 1)
          else if (k === Qt.Key_Left) root.columns > 1 ? root.move(-1) : root.setTier(root.tierIndex - 1)
          else if (k === Qt.Key_Right) root.columns > 1 ? root.move(1) : root.setTier(root.tierIndex + 1)
          else if (k === Qt.Key_Up) root.move(-root.columns)
          else if (k === Qt.Key_Down) root.move(root.columns)
          else if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) root.toggleLearned(root.selectedIndex)
          else if (k === Qt.Key_H) { root.hideLearned = !root.hideLearned; root.rebuild() }
          else return
          event.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.xxl

        // Header: title + tier tabs
        Item {
          id: header
          width: parent.width
          height: Math.max(titleCol.height, tabs.height)

          Column {
            id: titleCol
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.xs

            Text {
              text: Object.keys(root.herdrKeys).length ? "Learn Omarchy & herdr" : "Learn Omarchy"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }
            Text {
              text: root.tiers.length ? root.tiers[root.tierIndex].blurb : ""
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Row {
            id: tabs
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md

            Repeater {
              model: root.tiers

              delegate: Rectangle {
                required property int index
                required property var modelData
                readonly property bool active: index === root.tierIndex
                readonly property var progress: { root.learned; root.bindings; root.herdrKeys; return root.learnedCount(modelData) }

                width: tabText.implicitWidth + Style.spacing.controlPaddingX * 2
                height: tabText.implicitHeight + Style.spacing.controlPaddingY * 2
                radius: root.cornerRadius
                color: active ? root.selectedBackground : "transparent"
                border.width: active ? Math.max(1, Style.space(1)) : 0
                border.color: root.accent

                Text {
                  id: tabText
                  anchors.centerIn: parent
                  text: (index + 1) + "  " + modelData.name + "   " + progress.learned + "/" + progress.total
                  color: active || (progress.total > 0 && progress.learned === progress.total) ? root.accent : root.foreground
                  opacity: active ? 1 : 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setTier(index)
                }
              }
            }
          }
        }

        // Entries
        GridView {
          id: grid
          width: parent.width
          height: parent.height - header.height - footer.height - parent.spacing * 2
          model: entryModel
          clip: true
          cellWidth: Math.floor(width / root.columns)
          cellHeight: root.rowHeight
          boundsBehavior: Flickable.StopAtBounds

          delegate: Rectangle {
            id: row
            required property int index
            required property string desc
            required property string label
            required property string hint
            required property string combosJson

            readonly property bool isLearned: root.learned[desc] === true
            readonly property bool hasCursor: index === root.selectedIndex
            readonly property var combos: JSON.parse(combosJson)

            width: grid.cellWidth - Style.spacing.md
            height: grid.cellHeight - Style.spacing.sm
            radius: root.cornerRadius
            color: hasCursor ? root.selectedBackground : "transparent"

            Row {
              id: capsRow
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              width: Math.round(row.width * 0.36)
              spacing: Style.spacing.lg
              opacity: row.isLearned ? 0.45 : 1

              Repeater {
                model: row.combos

                delegate: Row {
                  required property var modelData
                  spacing: Style.spacing.sm

                  Repeater {
                    model: modelData

                    delegate: Rectangle {
                      required property string modelData
                      width: Math.max(height, capText.implicitWidth + Style.spacing.lg * 2)
                      height: capText.implicitHeight + Style.spacing.sm * 2
                      radius: Math.min(root.cornerRadius, Style.space(5))
                      color: Util.alpha(root.foreground, 0.06)
                      border.width: Math.max(1, Style.space(1))
                      border.color: Util.alpha(root.foreground, 0.3)

                      Text {
                        id: capText
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }
                    }
                  }
                }
              }
            }

            Column {
              anchors.left: capsRow.right
              anchors.leftMargin: Style.spacing.lg
              anchors.right: check.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xxs
              opacity: row.isLearned ? 0.45 : 1

              Text {
                width: parent.width
                text: row.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                visible: row.hint !== ""
                text: row.hint
                color: root.foreground
                opacity: 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            Text {
              id: check
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.lg
              anchors.verticalCenter: parent.verticalCenter
              text: row.isLearned ? "✓" : (row.hasCursor ? "○" : " ")
              color: row.isLearned ? root.accent : root.foreground
              opacity: row.isLearned ? 1 : 0.4
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.selectedIndex = row.index
              onClicked: root.toggleLearned(row.index)
            }
          }

          Text {
            anchors.centerIn: parent
            visible: entryModel.count === 0 && root.tiers.length > 0
            text: root.hideLearned ? "All learned here. Press H to show them again." : "Loading keybindings…"
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        Text {
          id: footer
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Click or Space: mark learned   ·   1–" + Math.max(1, root.tiers.length) + " / Tab: switch tier   ·   H: "
            + (root.hideLearned ? "show" : "hide") + " learned   ·   Super+K: all bindings   ·   Esc: close"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }
    }
  }
}
