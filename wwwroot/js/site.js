var map;
var routingControl = null;
var startPoint = null;
var endPoint = null;
var markerA = null;
var markerB = null;
var userMarker = null;

function initAmbulanceMap() {
    var container = L.DomUtil.get('map');
    if (container != null) { container._leaflet_id = null; }

    map = L.map('map').setView([10.762622, 106.660172], 15);

    var lightLayer = L.tileLayer(
    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'
);

var darkLayer = L.tileLayer(
    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
);

lightLayer.addTo(map);

    map.on("click", function (e) {
        if (!startPoint) {
            startPoint = e.latlng;

            markerA = L.marker(startPoint)
                .addTo(map)
                .bindPopup("🚑 Điểm A")
                .openPopup();
        }
        else if (!endPoint) {
            endPoint = e.latlng;

            markerB = L.marker(endPoint)
                .addTo(map)
                .bindPopup("🏥 Điểm B")
                .openPopup();

            drawRoute(startPoint, endPoint);
        }
        else {
            resetMap();
        }
    });

    coreLocateUser();
}

var isDark = false;

function coreToggleTheme() {
    document.body.classList.toggle("dark");

    if (!isDark) {
        map.removeLayer(lightLayer);
        darkLayer.addTo(map);
        isDark = true;
    } else {
        map.removeLayer(darkLayer);
        lightLayer.addTo(map);
        isDark = false;
    }
}

function resetMap() {
    if (markerA) map.removeLayer(markerA);
    if (markerB) map.removeLayer(markerB);
    if (routingControl) map.removeControl(routingControl);

    startPoint = null;
    endPoint = null;
    markerA = null;
    markerB = null;
    routingControl = null;
}

function coreCompleteCase() {
    resetMap();
    alert("🚑 Đã hoàn thành ca!");
}

function coreLocateUser() {
    navigator.geolocation.getCurrentPosition(function (p) {
        const latlng = [p.coords.latitude, p.coords.longitude];

        map.setView(latlng, 17);

        if (userMarker) map.removeLayer(userMarker);

        userMarker = L.marker(latlng)
            .addTo(map)
            .bindPopup("📍 Vị trí của bạn")
            .openPopup();
    }, function () {
        alert("Không lấy được vị trí!");
    });
}

function coreToggleTheme() {
    document.body.classList.toggle("dark");
}

function toggleRoutePanel() {
    var panel = document.querySelector(".leaflet-routing-container");

    if (!panel) return;

    var isHidden = panel.style.display === "none";

    panel.style.display = isHidden ? "block" : "none";

    var btn = document.getElementById("toggleRoute");
    if (btn) {
        btn.innerText = isHidden
            ? "✕ Hiện chỉ đường"
            : "✕ Ẩn chỉ đường";
    }
}