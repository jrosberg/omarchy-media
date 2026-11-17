import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import qs.Commons as Commons

BarWidget {
  id: root
  moduleName: "omarchy.media"

  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("omarchy.media")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property bool isPlaying: !!activePlayer && !!activePlayer.isPlaying
  readonly property string playIcon: activePlayer && activePlayer.isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? cleanArtist(activePlayer.trackArtist) : ""

  property bool popupOpen: false

  property bool settingsOpen: false
  onPopupOpenChanged: if (!popupOpen) settingsOpen = false

  function close() { popupOpen = false }

  // User-tunable settings, kept on this widget's shell.json layout entry.
  readonly property int scrollSpeedMin: 10
  readonly property int scrollSpeedMax: 200
  readonly property int labelWidthMin: 60
  readonly property int labelWidthMax: 600

  function numberSetting(name, fallback, min, max) {
    var value = Number(setting(name, fallback))
    if (!isFinite(value)) value = fallback
    return Math.max(min, Math.min(max, Math.round(value)))
  }

  // Pixels per second.
  readonly property int scrollSpeed: numberSetting("scrollSpeed", 40, scrollSpeedMin, scrollSpeedMax)
  readonly property real maxLabelWidth: numberSetting("labelWidth", 180, labelWidthMin, labelWidthMax)
  readonly property bool scrollOnce: setting("scrollOnce", false) === true
  readonly property bool stripTopic: setting("stripTopic", true) !== false

  // YouTube's auto-generated artist channels are named "<artist> - Topic",
  // and the browser reports the channel name as the track's artist.
  function cleanArtist(name) {
    var text = String(name || "")
    return stripTopic ? text.replace(/\s+-\s+Topic$/, "") : text
  }

  // Applied locally first so the bar follows a slider as it is dragged;
  // `persist` then writes the entry to shell.json, which comes back through
  // the bar as the same value on every monitor.
  function updateSettings(values, persist) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (persist && root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  visible: hasMedia
  implicitWidth: hasMedia ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      id: glyph
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: root.playIcon
      color: activePlayer && activePlayer.isPlaying ? root.bar.barForeground : Qt.darker(root.bar.barForeground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: Style.duration(160) }
      }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.title !== ""

      Text {
        id: labelText
        textFormat: Text.PlainText
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter

        property bool needsScroll: implicitWidth > scrollClip.width
        // With "scroll once" on, set when this title has had its one pass since
        // playback last started.
        property bool scrolledOnce: false
        onTextChanged: {
          scrolledOnce = false
          fadeIn.restart()
        }

        // A new title fades in rather than popping into the bar.
        NumberAnimation {
          id: fadeIn
          target: labelText
          property: "opacity"
          from: 0
          to: 1
          duration: Style.duration(240)
          easing.type: Easing.OutCubic
        }

        function scrollDuration(distance) {
          return Style.duration(Math.max(1, distance) / root.scrollSpeed * 1000)
        }

        Connections {
          target: root
          function onScrollOnceChanged() { labelText.scrolledOnce = false }
          // Pausing re-arms the one pass, so pressing play scrolls the title again.
          function onIsPlayingChanged() { if (!root.isPlaying) labelText.scrolledOnce = false }
        }

        // Each frame of the scroll redraws the bar, so it only runs while the
        // track is playing and the bar is on screen to show it. One pass
        // scrolls the title out to the left and back in from the right, so it
        // starts and ends reading from its start.
        SequentialAnimation on x {
          id: scrollAnim
          running: labelText.needsScroll && root.isPlaying && root.visible && !root.bar.barHidden && !root.popupOpen && !root.bar.vertical && !Style.reduceMotion
            && !(root.scrollOnce && labelText.scrolledOnce)
          // Stopped, the title reads from its start again.
          onRunningChanged: if (!running) labelText.x = 0
          onFinished: labelText.scrolledOnce = true
          loops: root.scrollOnce ? 1 : Animation.Infinite

          NumberAnimation {
            duration: labelText.scrollDuration(labelText.implicitWidth)
            from: 0
            to: -labelText.implicitWidth
            easing.type: Easing.Linear
          }
          NumberAnimation {
            duration: labelText.scrollDuration(scrollClip.width)
            from: scrollClip.width
            to: 0
            easing.type: Easing.Linear
          }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (!root.activePlayer) return
      if (mouse.button === Qt.MiddleButton) {
        if (root.mediaService) root.mediaService.runAction("next", false)
      } else if (mouse.button === Qt.RightButton) {
        root.popupOpen = !root.popupOpen
      } else {
        if (root.mediaService) root.mediaService.runAction("playPause", false)
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0 && root.mediaService) root.mediaService.runAction("previous", false)
      else if (wheel.angleDelta.y < 0 && root.mediaService) root.mediaService.runAction("next", false)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : "")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        spacing: Style.space(10)
        width: parent.width

        BorderSurface {
          width: Style.space(64)
          height: Style.space(64)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Commons.Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent)

          // Decode the art at the size it is drawn, not the size the player
          // serves it at. The popup is built on every monitor at startup.
          SizedImage {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            crop: true
            url: root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
            visible: url != ""
          }

          Text {
            anchors.centerIn: parent
            visible: !root.activePlayer || !root.activePlayer.trackArtUrl
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          spacing: Style.space(4)
          width: parent.width - Style.space(64) - settingsButton.width - parent.spacing * 2

          Text {
            id: popupTitle
            textFormat: Text.PlainText
            text: root.title || I18n.t("media.nothingPlaying")
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width

            HoverHandler { id: popupTitleHover }

            // The full title, only when it does not fit and is cut with "…".
            PanelToolTip {
              visible: popupTitle.truncated && popupTitleHover.hovered
              text: popupTitle.text
              width: Math.min(implicitWidth, column.width)
            }
          }

          Text {
            textFormat: Text.PlainText
            text: root.artist
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            textFormat: Text.PlainText
            text: root.activePlayer && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }

        Button {
          id: settingsButton
          iconText: "󰒓"
          tooltipText: strings.t("settings.tooltip")
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingY
          verticalPadding: Style.spacing.controlPaddingY
          selected: root.settingsOpen
          onClicked: root.settingsOpen = !root.settingsOpen
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)
        // Transport controls keep previous, play, next in every language,
        // matching their glyphs; media controls are not mirrored.
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        Button {
          iconText: "󰒮"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: "󰒭"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
        }
      }

      PanelSeparator {
        visible: root.sourcePlayers.length > 1
        foreground: root.bar.foreground
      }

      Column {
        id: sourceList
        visible: root.sourcePlayers.length > 1
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.sourcePlayers

          BorderSurface {
            id: sourceRow
            required property var modelData

            readonly property var player: modelData
            readonly property bool selected: root.activePlayer && player
              && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
            readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || I18n.t("media.mediaSource")) : I18n.t("media.mediaSource")
            readonly property string sourceDetail: player && player.trackArtist ? root.cleanArtist(player.trackArtist) : (player && player.identity ? player.identity : "")

            width: sourceList.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: selected ? Style.selectedFillFor(root.bar.foreground, Commons.Color.accent) : "transparent"
            borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Commons.Color.accent) : Border.none()

            Row {
              id: sourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: sourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(26)
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceTitle
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceRow.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: sourceRow.sourceDetail
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
            }
          }
        }
      }

      PanelSeparator {
        visible: root.settingsOpen
        foreground: root.bar.foreground
      }

      Column {
        id: settingsList
        visible: root.settingsOpen
        width: parent.width
        spacing: Style.space(6)

        component SettingSlider: Column {
          id: sliderRow

          property string label: ""
          property string valueFormat: "%1"
          property string settingName: ""
          property alias value: slider.value
          property alias minimum: slider.minimum
          property alias maximum: slider.maximum
          property alias step: slider.step

          width: settingsList.width
          spacing: Style.space(2)

          Item {
            width: parent.width
            height: sliderLabel.implicitHeight

            Text {
              id: sliderLabel
              textFormat: Text.PlainText
              anchors.left: parent.left
              text: sliderRow.label
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              text: sliderRow.valueFormat.arg(I18n.formatNumber(Math.round(slider.liveValue), 0))
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          PanelSlider {
            id: slider
            width: parent.width
            bar: root.bar
            integer: true

            function store(next, persist) {
              var values = {}
              values[sliderRow.settingName] = Math.round(next)
              root.updateSettings(values, persist)
            }

            onMoved: function(next) { store(next, false) }
            onReleased: function(next) { store(next, true) }
          }
        }

        SettingSlider {
          label: strings.t("settings.scrollSpeed")
          valueFormat: strings.t("settings.scrollSpeedValue")
          settingName: "scrollSpeed"
          value: root.scrollSpeed
          minimum: root.scrollSpeedMin
          maximum: root.scrollSpeedMax
          step: 5
        }

        SettingSlider {
          label: strings.t("settings.titleWidth")
          valueFormat: strings.t("settings.titleWidthValue")
          settingName: "labelWidth"
          value: root.maxLabelWidth
          minimum: root.labelWidthMin
          maximum: root.labelWidthMax
          step: 10
        }

        Toggle {
          width: parent.width
          label: strings.t("settings.scrollOnce")
          description: strings.t("settings.scrollOnceDescription")
          checked: root.scrollOnce
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          titleSize: Style.font.bodySmall
          onClicked: root.updateSettings({ scrollOnce: !root.scrollOnce }, true)
        }

        Toggle {
          width: parent.width
          label: strings.t("settings.stripTopic")
          description: strings.t("settings.stripTopicDescription")
          checked: root.stripTopic
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          titleSize: Style.font.bodySmall
          onClicked: root.updateSettings({ stripTopic: !root.stripTopic }, true)
        }
      }
    }
  }
}
