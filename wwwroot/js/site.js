// Khởi tạo bản đồ
var map = L.map('map').setView([10.762622, 106.660172], 15);

// Load OpenStreetMap
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19
}).addTo(map);

// Điểm A & B
let startPoint = null;
let endPoint = null;
let routingControl = null;

map.on("click", function (e) {

    // CLICK 1 → điểm A
    if (!startPoint) {
        startPoint = L.marker(e.latlng).addTo(map)
            .bindPopup("🚑 Điểm A (Xe cấp cứu)")
            .openPopup();
        return;
    }

    // CLICK 2 → điểm B
    if (!endPoint) {
        endPoint = L.marker(e.latlng).addTo(map)
            .bindPopup("🏥 Điểm B (Bệnh viện)")
            .openPopup();

        // xoá route cũ nếu có
        if (routingControl) {
            map.removeControl(routingControl);
        }

        // VẼ ĐƯỜNG THEO ĐƯỜNG THẬT
        routingControl = L.Routing.control({
            waypoints: [
                startPoint.getLatLng(),
                endPoint.getLatLng()
            ],
            addWaypoints: false,
            draggableWaypoints: false,
            routeWhileDragging: false,
            show: false,
            createMarker: () => null
        }).addTo(map);

        return;
    }

    // CLICK 3 → RESET
    map.removeLayer(startPoint);
    map.removeLayer(endPoint);
    if (routingControl) map.removeControl(routingControl);

    startPoint = null;
    endPoint = null;
    routingControl = null;
});



    