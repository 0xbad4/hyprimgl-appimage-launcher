import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    LauncherSettings { id: cfg }

    property var entries: []
    property string query: ""
    property string scanDir: ""
    property bool loaded: false
    readonly property string family: cfg.fontFamily !== "" ? cfg.fontFamily : Qt.application.font.family

    ListModel { id: shown }

    Timer {
        id: refreshTimer
        interval: 30
        onTriggered: root.refilter(true)
    }

    function upsert(obj) {
        const list = entries;
        for (let i = 0; i < list.length; i++) {
            if (list[i].path === obj.path) {
                list[i] = obj;
                return;
            }
        }
        list.push(obj);
    }

    function handleLine(line) {
        let obj;
        try {
            obj = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (obj.dir !== undefined) {
            scanDir = obj.dir;
        } else if (obj.path !== undefined) {
            upsert(obj);
            refreshTimer.restart();
        }
    }

    function refilter(keepSelection) {
        const q = query.trim().toLowerCase();
        const prev = keepSelection && grid.currentIndex >= 0 && grid.currentIndex < shown.count
            ? shown.get(grid.currentIndex).appPath : "";
        const rows = [];
        for (const e of entries) {
            const key = e.name.toLowerCase();
            let rank = 0;
            if (q !== "") {
                const at = key.indexOf(q);
                if (at < 0)
                    continue;
                rank = at === 0 ? 0 : 1;
            }
            rows.push({ e: e, key: key, rank: rank });
        }
        rows.sort((a, b) => a.rank - b.rank || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
        shown.clear();
        let sel = 0;
        for (let i = 0; i < rows.length; i++) {
            const e = rows[i].e;
            shown.append({ appPath: e.path, appName: e.name, appIcon: e.icon });
            if (e.path === prev)
                sel = i;
        }
        grid.currentIndex = rows.length > 0 ? sel : -1;
    }

    function launch(path) {
        Quickshell.execDetached([
            "sh", "-c",
            'cd "$HOME" 2>/dev/null; [ -x "$1" ] || chmod u+x "$1"; exec "$1"',
            "sh", path
        ]);
        if (cfg.closeOnLaunch)
            Qt.quit();
    }

    function launchCurrent() {
        if (grid.currentIndex >= 0 && grid.currentIndex < shown.count)
            launch(shown.get(grid.currentIndex).appPath);
    }

    Process {
        running: true
        command: ["python3", Quickshell.shellPath("scripts/appimage-index.py")]
        stdout: SplitParser {
            onRead: data => root.handleLine(data)
        }
        onExited: {
            root.loaded = true;
            root.refilter(true);
        }
    }

    FloatingWindow {
        id: win
        title: cfg.title
        implicitWidth: cfg.width
        implicitHeight: cfg.height
        color: cfg.background
        onVisibleChanged: if (!visible) Qt.quit()

        Item {
            anchors.fill: parent
            focus: true
            property bool hadFocus: false

            Window.onActiveChanged: {
                if (Window.active)
                    hadFocus = true;
                else if (hadFocus && cfg.closeOnFocusLoss)
                    Qt.quit();
            }

            Rectangle {
                id: searchBox
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: cfg.padding
                height: cfg.searchHeight
                radius: cfg.radius
                color: cfg.surface
                border.width: 1
                border.color: input.activeFocus ? cfg.accent : "transparent"

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    focus: true
                    color: cfg.text
                    selectionColor: cfg.accent
                    selectedTextColor: cfg.background
                    font.family: root.family
                    font.pixelSize: cfg.fontSize + 2

                    Component.onCompleted: forceActiveFocus()

                    onTextChanged: {
                        root.query = text;
                        root.refilter(false);
                    }

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Down:
                            grid.moveCurrentIndexDown();
                            break;
                        case Qt.Key_Up:
                            grid.moveCurrentIndexUp();
                            break;
                        case Qt.Key_Left:
                            grid.moveCurrentIndexLeft();
                            break;
                        case Qt.Key_Right:
                            grid.moveCurrentIndexRight();
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.launchCurrent();
                            break;
                        case Qt.Key_Escape:
                            if (text !== "")
                                text = "";
                            else if (cfg.closeOnEscape)
                                Qt.quit();
                            break;
                        default:
                            return;
                        }
                        event.accepted = true;
                    }

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: input.text === ""
                        text: cfg.placeholder
                        color: cfg.muted
                        font.family: root.family
                        font.pixelSize: cfg.fontSize + 2
                    }
                }
            }

            GridView {
                id: grid
                anchors.top: searchBox.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: cfg.padding
                anchors.topMargin: 6
                clip: true
                model: shown
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                cellWidth: Math.floor(width / Math.max(1, Math.floor(width / cfg.tileWidth)))
                cellHeight: cfg.tileHeight

                delegate: Item {
                    id: tile
                    required property int index
                    required property string appPath
                    required property string appName
                    required property string appIcon
                    readonly property bool selected: GridView.isCurrentItem

                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: cfg.radius
                        color: tile.selected ? cfg.surface
                             : area.containsMouse ? Qt.alpha(cfg.surface, 0.5) : "transparent"
                        border.width: tile.selected ? 1 : 0
                        border.color: cfg.accent
                    }

                    Column {
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 12
                        spacing: 6

                        Item {
                            width: cfg.iconSize
                            height: cfg.iconSize
                            anchors.horizontalCenter: parent.horizontalCenter

                            Rectangle {
                                anchors.fill: parent
                                radius: cfg.radius
                                color: cfg.tile
                                visible: iconImage.status !== Image.Ready

                                Text {
                                    anchors.centerIn: parent
                                    text: tile.appName.charAt(0).toUpperCase()
                                    color: cfg.text
                                    font.family: root.family
                                    font.pixelSize: Math.round(cfg.iconSize * 0.5)
                                    font.bold: true
                                }
                            }

                            Image {
                                id: iconImage
                                anchors.fill: parent
                                source: tile.appIcon !== "" ? "file://" + tile.appIcon : ""
                                sourceSize: Qt.size(cfg.iconSize * 2, cfg.iconSize * 2)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                                cache: false
                                smooth: true
                            }
                        }

                        Text {
                            width: parent.width
                            text: tile.appName
                            color: cfg.text
                            font.family: root.family
                            font.pixelSize: cfg.fontSize
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.launch(tile.appPath)
                    }
                }
            }

            Text {
                anchors.centerIn: grid
                visible: shown.count === 0 && (root.query !== "" || root.loaded)
                horizontalAlignment: Text.AlignHCenter
                color: cfg.muted
                font.family: root.family
                font.pixelSize: cfg.fontSize
                text: root.query !== "" ? "No matches" : "No AppImages in\n" + root.scanDir
            }
        }
    }
}
