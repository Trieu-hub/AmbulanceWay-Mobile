var map;
let routingControl = null;
let startPoint = null;
let endPoint = null;
let markerA = null;
let markerB = null;
let userMarker = null;
let isDark = false;

var lightLayer, darkLayer;

if (typeof L !== 'undefined') {
    lightLayer = L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png');
    darkLayer = L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png');
}

function initAmbulanceMap() {
    const container = L.DomUtil.get('map');
    if (container && container._leaflet_id !== undefined) {
        if (map) { map.remove(); }
        container._leaflet_id = null;
    }

    map = L.map('map').setView([10.762622, 106.660172], 15);

    // Thiết lập layer ban đầu dựa trên class của body
    isDark = document.body.classList.contains("dark");
    const currentLayer = isDark ? darkLayer : lightLayer;
    currentLayer.addTo(map);

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

            if (typeof drawRoute === "function") {
                drawRoute(startPoint, endPoint);
            }
        }
        else {
            resetMap();
        }
    });

    coreLocateUser();
}

function coreToggleTheme() {
    isDark = document.body.classList.toggle("dark");

    if (isDark) {
        map.removeLayer(lightLayer);
        darkLayer.addTo(map);
    } else {
        map.removeLayer(darkLayer);
        lightLayer.addTo(map);
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

function toggleRoutePanel() {
    const panel = document.querySelector(".leaflet-routing-container");

    if (!panel) return;

    const isHidden = panel.style.display === "none";

    panel.style.display = isHidden ? "block" : "none";

    const btn = document.getElementById("toggleRoute");
    if (btn) {
        btn.innerText = isHidden
            ? "✕ Hiện chỉ đường"
            : "✕ Ẩn chỉ đường";
    }
}

// Global toast util (for admin pages)
function showToast(message, type = 'info') {
    // Fallback if no toast container
    if (typeof bootstrap === 'undefined') {
        alert(message);
        return;
    }
    
    const toastId = type === 'success' ? 'successToast' : type === 'error' ? 'errorToast' : 'infoToast';
    const toastEl = document.getElementById(toastId);
    if (!toastEl) {
        console.warn('No toast element:', toastId);
        alert(message);
        return;
    }
    
    const toastBody = toastEl.querySelector('.toast-body');
    toastBody.innerHTML = `<i class="fa-solid fa-${type === 'success' ? 'check-circle' : type === 'error' ? 'exclamation-triangle' : 'info-circle'} me-2"></i>${message}`;
    
    const bsToast = new bootstrap.Toast(toastEl);
    bsToast.show();
}

// Network status toast
function showNetworkStatus(status) {
    showToast(`Kết nối: ${status === 'online' ? 'Trực tuyến' : 'Ngoại tuyến'}`, status === 'online' ? 'success' : 'warning');
}
