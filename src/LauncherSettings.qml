import QtQuick

QtObject {
    readonly property string title: "hyprimgl"
    readonly property int width: 420
    readonly property int height: 320
    readonly property int padding: 10
    readonly property int searchHeight: 38
    readonly property int iconSize: 40
    readonly property int tileWidth: 100
    readonly property int tileHeight: 88
    readonly property int radius: 10
    readonly property int fontSize: 12
    readonly property string fontFamily: ""
    readonly property string placeholder: "Search AppImages"
    readonly property bool closeOnLaunch: true
    readonly property bool closeOnEscape: true
    readonly property bool closeOnFocusLoss: true

    readonly property color background: "#2e3440"
    readonly property color surface: "#3b4252"
    readonly property color tile: "#4c566a"
    readonly property color accent: "#88c0d0"
    readonly property color text: "#eceff4"
    readonly property color muted: "#9aa5b8"
}
