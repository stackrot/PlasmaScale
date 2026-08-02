import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    property string backendState: "Unknown"
    property var selfNode: ({
    })
    property var devices: []
    property var exitNodes: []
    property var activeExitNode: null
    property bool exitNodeActive: activeExitNode !== null
    property string lastError: ""
    property bool pendingAction: false
    property bool refreshing: false
    readonly property bool running: backendState === "Running"

    function flag(countryCode) {
        if (!countryCode || countryCode.length !== 2)
            return "";

        const regionalIndicatorA = 127462;
        const code = countryCode.toUpperCase();
        return String.fromCodePoint(regionalIndicatorA + code.charCodeAt(0) - 65) + String.fromCodePoint(regionalIndicatorA + code.charCodeAt(1) - 65);
    }

    function cleanName(hostname, dnsName) {
        const cleanedHostname = (hostname || "").trim();
        if (cleanedHostname && cleanedHostname.toLowerCase() !== "localhost")
            return cleanedHostname;

        const dnsLabel = (dnsName || "").replace(/\.$/, "").split(".")[0];
        return dnsLabel || cleanedHostname || "(unknown)";
    }

    function osIcon(osName) {
        switch ((osName || "").toLowerCase()) {
        case "android":
        case "ios":
            return "phone";
        case "windows":
        case "linux":
            return "computer";
        case "macos":
            return "computer-laptop";
        default:
            return "network-server";
        }
    }

    function exitLabel(node) {
        if (!node)
            return "";

        if (node.city && node.country)
            return node.city + ", " + node.country;

        return node.hostname || node.ip || "";
    }

    function activeExitText() {
        if (!activeExitNode)
            return "";

        const countryFlag = flag(activeExitNode.countryCode);
        const prefix = countryFlag ? countryFlag + "  " : "";
        return prefix + "Exit node: " + exitLabel(activeExitNode);
    }

    function isRealTime(timestamp) {
        const milliseconds = Date.parse(timestamp);
        return !isNaN(milliseconds) && new Date(milliseconds).getFullYear() >= 2000;
    }

    function relativeTime(timestamp) {
        if (!timestamp)
            return "—";

        const milliseconds = Date.parse(timestamp);
        if (isNaN(milliseconds))
            return "—";

        const date = new Date(milliseconds);
        if (date.getFullYear() < 2000)
            return "never";

        const seconds = Math.max(0, Math.floor((Date.now() - milliseconds) / 1000));
        if (seconds < 60)
            return seconds + "s ago";

        if (seconds < 3600)
            return Math.floor(seconds / 60) + "m ago";

        if (seconds < 86400)
            return Math.floor(seconds / 3600) + "h ago";

        return Math.floor(seconds / 86400) + "d ago";
    }

    function formatBytes(bytes) {
        let amount = bytes || 0;
        if (amount < 1024)
            return amount + " B";

        const units = ["KiB", "MiB", "GiB", "TiB"];
        let unitIndex = -1;
        do {
            amount /= 1024;
            unitIndex++;
        } while (amount >= 1024 && unitIndex < units.length - 1)
        return amount.toFixed(1) + " " + units[unitIndex];
    }

    function refresh() {
        if (!refreshing) {
            refreshing = true;
            executable.exec("tailscale status --json");
        }
    }

    function runAction(command) {
        if (pendingAction)
            return false;

        pendingAction = true;
        lastError = "";
        executable.exec(command);
        return true;
    }

    function tsUp() {
        runAction("tailscale up");
    }

    function tsDown() {
        runAction("tailscale down");
    }

    function setExit(ip) {
        if (!/^[0-9a-fA-F:.]+$/.test(ip)) {
            lastError = "Invalid exit node address";
            return false;
        }
        return runAction("tailscale set --exit-node=" + ip);
    }

    function clearExit() {
        runAction("tailscale set --exit-node=");
    }

    function parseStatus(text) {
        try {
            const status = JSON.parse(text);
            backendState = status.BackendState || "Unknown";
            const localNode = status.Self || {
            };
            selfNode = {
                "hostname": cleanName(localNode.HostName, localNode.DNSName),
                "ip": (localNode.TailscaleIPs || [])[0] || "",
                "ips": localNode.TailscaleIPs || [],
                "os": localNode.OS || "",
                "online": !!localNode.Online,
                "dns": (localNode.DNSName || "").replace(/\.$/, "")
            };
            const peers = status.Peer || {
            };
            const parsedDevices = [];
            const cityGroups = {
            };
            const standaloneExits = [];
            let activeExit = null;
            for (const peerKey in peers) {
                const peer = peers[peerKey];
                const location = peer.Location || {
                };
                const hostname = cleanName(peer.HostName, peer.DNSName);
                const ip = (peer.TailscaleIPs || [])[0] || "";
                const city = (location.City || "").replace(/, [A-Z]{2}$/, "");
                const country = location.Country || "";
                const countryCode = location.CountryCode || "";
                const displayCountry = country || "Other";
                const hasLocation = city !== "" || country !== "" || countryCode !== "";
                const priority = location.Priority !== undefined ? location.Priority : -1;
                const key = city ? countryCode + "|" + country + "|" + city : "peer|" + peer.ID;
                if (!peer.ExitNodeOption || !hasLocation)
                    parsedDevices.push({
                        "id": peer.ID,
                        "hostname": hostname,
                        "dns": (peer.DNSName || "").replace(/\.$/, ""),
                        "ip": ip,
                        "ips": peer.TailscaleIPs || [],
                        "os": peer.OS || "",
                        "online": !!peer.Online,
                        "rx": peer.RxBytes || 0,
                        "tx": peer.TxBytes || 0,
                        "lastHandshake": peer.LastHandshake || "",
                        "lastSeen": peer.LastSeen || "",
                        "exitOption": !!peer.ExitNodeOption,
                        "isExit": !!peer.ExitNode
                    });

                if (!peer.ExitNodeOption)
                    continue;

                if (peer.ExitNode)
                    activeExit = {
                        "id": peer.ID,
                        "country": displayCountry,
                        "countryCode": countryCode,
                        "city": city || hostname,
                        "hostname": hostname,
                        "ip": ip,
                        "key": key
                    };

                if (!city) {
                    standaloneExits.push({
                        "key": key,
                        "country": displayCountry,
                        "countryCode": countryCode,
                        "city": hostname,
                        "hostname": hostname,
                        "ip": ip,
                        "online": !!peer.Online,
                        "count": 1
                    });
                    continue;
                }
                let group = cityGroups[key];
                if (!group)
                    group = cityGroups[key] = {
                        "key": key,
                        "country": displayCountry,
                        "countryCode": countryCode,
                        "city": city,
                        "hostname": hostname,
                        "ip": "",
                        "online": false,
                        "count": 0,
                        "priority": -1
                    };

                group.count++;
                const betterRepresentative = (!!peer.Online && !group.online) || (!!peer.Online === group.online && priority > group.priority);
                if (group.ip === "" || betterRepresentative) {
                    group.hostname = hostname;
                    group.ip = ip;
                    group.priority = priority;
                }
                group.online = group.online || !!peer.Online;
            }
            let parsedExits = [];
            for (const cityKey in cityGroups) {
                parsedExits.push(cityGroups[cityKey]);
            }
            parsedExits = parsedExits.concat(standaloneExits);
            parsedDevices.sort(function(first, second) {
                if (first.online !== second.online)
                    return first.online ? -1 : 1;

                return first.hostname.toLowerCase().localeCompare(second.hostname.toLowerCase());
            });
            parsedExits.sort(function(first, second) {
                const countryOrder = first.country.localeCompare(second.country);
                if (countryOrder !== 0)
                    return countryOrder;

                return first.city.localeCompare(second.city);
            });
            devices = parsedDevices;
            exitNodes = parsedExits;
            activeExitNode = activeExit;
            lastError = "";
        } catch (e) {
            lastError = "Parse error: " + e;
        }
    }

    function copyText(text) {
        clipHelper.text = text;
        clipHelper.selectAll();
        clipHelper.copy();
    }

    Plasmoid.icon: running ? "network-vpn" : "network-disconnect"
    Plasmoid.status: backendState === "NeedsLogin" ? PlasmaCore.Types.NeedsAttentionStatus : running ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus
    toolTipMainText: "Tailscale"
    toolTipSubText: running ? (exitNodeActive ? "Connected · exit node: " + exitLabel(activeExitNode) : "Connected" + (selfNode.ip ? " · " + selfNode.ip : "")) : "Disconnected (" + backendState + ")"

    P5Support.DataSource {
        id: executable

        function exec(command) {
            connectSource(command);
        }

        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            const code = data["exit code"];
            const output = data["stdout"];
            const errorOutput = data["stderr"];
            executable.disconnectSource(source);
            if (source.indexOf("status --json") !== -1) {
                root.refreshing = false;
                if (code === 0)
                    root.parseStatus(output);
                else
                    root.lastError = (errorOutput && errorOutput.trim()) || "tailscale status failed";
            } else {
                root.pendingAction = false;
                if (code === 0) {
                    root.lastError = "";
                    root.refresh();
                } else {
                    root.lastError = (errorOutput && errorOutput.trim()) || "Command failed";
                }
            }
        }
    }

    Timer {
        interval: root.expanded ? 5000 : 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    TextEdit {
        id: clipHelper

        visible: false
    }

    compactRepresentation: Item {
        id: compact

        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: root.expanded = !root.expanded
        }

        Kirigami.Icon {
            id: compactIcon

            anchors.fill: parent
            source: Qt.resolvedUrl("../icons/tailscale.svg")
            isMask: true
            color: Kirigami.Theme.textColor
            opacity: root.running ? 1 : 0.7
        }

        Rectangle {
            width: Math.max(6, parent.width * 0.36)
            height: width
            radius: width / 2
            color: root.running ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
            border.color: Kirigami.Theme.backgroundColor
            border.width: Math.max(1, width * 0.14)
            anchors.right: parent.right
            anchors.bottom: parent.bottom
        }

    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 21
        Layout.minimumHeight: Kirigami.Units.gridUnit * 24
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.preferredHeight: Kirigami.Units.gridUnit * 30

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Icon {
                    source: Qt.resolvedUrl("../icons/tailscale.svg")
                    isMask: true
                    color: Kirigami.Theme.textColor
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    opacity: root.running ? 1 : 0.55
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    PlasmaExtras.Heading {
                        level: 4
                        text: root.selfNode.hostname || "Tailscale"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            Layout.preferredWidth: Kirigami.Units.smallSpacing * 1.4
                            Layout.preferredHeight: Kirigami.Units.smallSpacing * 1.4
                            radius: width / 2
                            color: root.running ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                            Layout.alignment: Qt.AlignVCenter
                        }

                        PlasmaComponents.Label {
                            text: root.running ? "Connected" : root.backendState
                            font: Kirigami.Theme.smallFont
                            opacity: 0.8
                        }

                        PlasmaComponents.Label {
                            visible: root.selfNode.ip !== ""
                            text: "· " + root.selfNode.ip
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                    }

                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    display: QQC2.AbstractButton.IconOnly
                    text: "Refresh"
                    enabled: !root.refreshing
                    onClicked: root.refresh()
                    PlasmaComponents.ToolTip.text: "Refresh"
                    PlasmaComponents.ToolTip.visible: hovered
                }

                PlasmaComponents.Button {
                    text: root.running ? "Disconnect" : "Connect"
                    icon.name: root.running ? "network-disconnect" : "network-connect"
                    enabled: !root.pendingAction
                    onClicked: root.running ? root.tsDown() : root.tsUp()
                }

            }

            PlasmaComponents.Label {
                visible: root.lastError !== ""
                Layout.fillWidth: true
                text: root.lastError
                color: Kirigami.Theme.negativeTextColor
                font: Kirigami.Theme.smallFont
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.exitNodeActive
                radius: Kirigami.Units.smallSpacing
                color: Kirigami.Theme.positiveBackgroundColor
                implicitHeight: exitStrip.implicitHeight + Kirigami.Units.smallSpacing * 2

                RowLayout {
                    id: exitStrip

                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: root.activeExitText()
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    PlasmaComponents.Button {
                        text: "Disable"
                        icon.name: "dialog-close"
                        flat: true
                        enabled: !root.pendingAction
                        onClicked: root.clearExit()
                    }

                }

            }

            PlasmaComponents.TabBar {
                id: tabBar

                Layout.fillWidth: true

                PlasmaComponents.TabButton {
                    text: "Devices (" + root.devices.length + ")"
                    icon.name: "computer"
                }

                PlasmaComponents.TabButton {
                    text: "Exit nodes"
                    icon.name: "network-vpn"
                }

            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: tabBar.currentIndex

                PlasmaComponents.ScrollView {
                    PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
                    contentWidth: availableWidth

                    ListView {
                        id: devList

                        clip: true
                        model: root.devices
                        spacing: 0

                        PlasmaExtras.PlaceholderMessage {
                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.gridUnit * 4
                            visible: devList.count === 0
                            iconName: "network-disconnect"
                            text: root.running ? "No devices" : "Tailscale is not connected"
                        }

                        delegate: Item {
                            id: devDelegate

                            property bool open: false

                            width: ListView.view.width
                            implicitHeight: devCol.implicitHeight + Kirigami.Units.smallSpacing * 2

                            Rectangle {
                                anchors.fill: parent
                                color: devMouse.containsMouse ? Kirigami.Theme.highlightColor : "transparent"
                                opacity: devMouse.containsMouse ? 0.15 : 1
                                radius: Kirigami.Units.smallSpacing
                            }

                            MouseArea {
                                id: devMouse

                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: devDelegate.open = !devDelegate.open
                            }

                            ColumnLayout {
                                id: devCol

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Kirigami.Units.smallSpacing

                                    Rectangle {
                                        Layout.preferredWidth: Kirigami.Units.smallSpacing * 1.4
                                        Layout.preferredHeight: Kirigami.Units.smallSpacing * 1.4
                                        radius: width / 2
                                        color: modelData.online ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                                    }

                                    Kirigami.Icon {
                                        source: root.osIcon(modelData.os)
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                        opacity: modelData.online ? 1 : 0.5
                                    }

                                    PlasmaComponents.Label {
                                        text: modelData.hostname
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    PlasmaComponents.Label {
                                        text: modelData.ip
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.6
                                    }

                                    Kirigami.Icon {
                                        source: devDelegate.open ? "go-up" : "go-down"
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                        opacity: 0.5
                                    }

                                }

                                GridLayout {
                                    visible: devDelegate.open
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing
                                    columns: 2
                                    rowSpacing: 0
                                    columnSpacing: Kirigami.Units.smallSpacing

                                    PlasmaComponents.Label {
                                        text: "OS"
                                        opacity: 0.6
                                        font: Kirigami.Theme.smallFont
                                    }

                                    PlasmaComponents.Label {
                                        text: modelData.os || "—"
                                        font: Kirigami.Theme.smallFont
                                    }

                                    PlasmaComponents.Label {
                                        text: "DNS"
                                        opacity: 0.6
                                        font: Kirigami.Theme.smallFont
                                    }

                                    PlasmaComponents.Label {
                                        text: modelData.dns || "—"
                                        font: Kirigami.Theme.smallFont
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    PlasmaComponents.Label {
                                        text: "Addresses"
                                        opacity: 0.6
                                        font: Kirigami.Theme.smallFont
                                        Layout.alignment: Qt.AlignTop
                                    }

                                    PlasmaComponents.Label {
                                        text: (modelData.ips || []).join("\n") || "—"
                                        font: Kirigami.Theme.smallFont
                                        Layout.fillWidth: true
                                        wrapMode: Text.WrapAnywhere
                                    }

                                    PlasmaComponents.Label {
                                        text: modelData.online ? "Connection" : "Last seen"
                                        opacity: 0.6
                                        font: Kirigami.Theme.smallFont
                                    }

                                    PlasmaComponents.Label {
                                        font: Kirigami.Theme.smallFont
                                        text: modelData.online ? (root.isRealTime(modelData.lastHandshake) ? "direct, " + root.relativeTime(modelData.lastHandshake) : "no direct connection") : (root.isRealTime(modelData.lastSeen) ? root.relativeTime(modelData.lastSeen) : "—")
                                    }

                                    PlasmaComponents.Label {
                                        text: "Traffic"
                                        opacity: 0.6
                                        font: Kirigami.Theme.smallFont
                                    }

                                    PlasmaComponents.Label {
                                        text: "↓ " + root.formatBytes(modelData.rx) + "   ↑ " + root.formatBytes(modelData.tx)
                                        font: Kirigami.Theme.smallFont
                                    }

                                    RowLayout {
                                        Layout.columnSpan: 2
                                        Layout.fillWidth: true
                                        Layout.topMargin: Kirigami.Units.smallSpacing
                                        spacing: Kirigami.Units.smallSpacing

                                        PlasmaComponents.Button {
                                            text: "Copy IP"
                                            icon.name: "edit-copy"
                                            flat: true
                                            onClicked: root.copyText(modelData.ip)
                                        }

                                        PlasmaComponents.Button {
                                            visible: modelData.exitOption
                                            text: modelData.isExit ? "Active exit node" : "Use as exit node"
                                            icon.name: "network-vpn"
                                            flat: true
                                            enabled: !modelData.isExit && !root.pendingAction
                                            onClicked: root.setExit(modelData.ip)
                                        }

                                    }

                                }

                            }

                        }

                    }

                }

                ColumnLayout {
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.TextField {
                        id: exitSearch

                        Layout.fillWidth: true
                        placeholderText: "Filter by country or city…"
                        clearButtonShown: true
                    }

                    PlasmaComponents.Button {
                        Layout.fillWidth: true
                        text: "Direct connection (no exit node)"
                        icon.name: root.exitNodeActive ? "" : "dialog-ok"
                        checkable: false
                        flat: !root.exitNodeActive ? false : true
                        highlighted: !root.exitNodeActive
                        enabled: root.exitNodeActive && !root.pendingAction
                        onClicked: root.clearExit()
                    }

                    PlasmaComponents.ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
                        contentWidth: availableWidth

                        ListView {
                            id: exitList

                            clip: true
                            model: {
                                const query = exitSearch.text.toLowerCase().trim();
                                if (query === "")
                                    return root.exitNodes;

                                return root.exitNodes.filter(function(node) {
                                    return ((node.country || "") + " " + (node.city || "") + " " + (node.hostname || "")).toLowerCase().indexOf(query) !== -1;
                                });
                            }
                            section.property: "country"

                            PlasmaExtras.PlaceholderMessage {
                                anchors.centerIn: parent
                                width: parent.width - Kirigami.Units.gridUnit * 4
                                visible: exitList.count === 0
                                iconName: "network-vpn"
                                text: "No exit nodes match"
                            }

                            section.delegate: Rectangle {
                                width: ListView.view.width
                                implicitHeight: secLabel.implicitHeight + Kirigami.Units.smallSpacing
                                color: Kirigami.Theme.backgroundColor

                                PlasmaComponents.Label {
                                    id: secLabel

                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: Kirigami.Units.smallSpacing
                                    text: section
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    font.bold: true
                                    opacity: 0.7
                                }

                            }

                            delegate: Item {
                                id: exitDelegate

                                property bool isActive: root.activeExitNode && root.activeExitNode.key === modelData.key

                                width: ListView.view.width
                                implicitHeight: exitRow.implicitHeight + Kirigami.Units.smallSpacing

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Kirigami.Units.smallSpacing
                                    color: exitDelegate.isActive ? Kirigami.Theme.positiveBackgroundColor : exitMouse.containsMouse ? Kirigami.Theme.highlightColor : "transparent"
                                    opacity: exitDelegate.isActive ? 1 : (exitMouse.containsMouse ? 0.15 : 1)
                                }

                                MouseArea {
                                    id: exitMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !root.pendingAction
                                    onClicked: exitDelegate.isActive ? root.clearExit() : root.setExit(modelData.ip)
                                }

                                RowLayout {
                                    id: exitRow

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Kirigami.Units.smallSpacing
                                    spacing: Kirigami.Units.smallSpacing

                                    PlasmaComponents.Label {
                                        text: root.flag(modelData.countryCode)
                                        visible: text !== ""
                                    }

                                    PlasmaComponents.Label {
                                        text: modelData.city || modelData.hostname
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    PlasmaComponents.Label {
                                        visible: (modelData.count || 0) > 1
                                        text: modelData.count + " servers"
                                        font: Kirigami.Theme.smallFont
                                        opacity: 0.5
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: Kirigami.Units.smallSpacing * 1.2
                                        Layout.preferredHeight: Kirigami.Units.smallSpacing * 1.2
                                        radius: width / 2
                                        color: modelData.online ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor
                                        opacity: 0.7
                                    }

                                    Kirigami.Icon {
                                        visible: exitDelegate.isActive
                                        source: "dialog-ok"
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    }

                                }

                            }

                        }

                    }

                }

            }

        }

    }

}
